#!/usr/bin/env bash
#
# Run 6: fast C-exact interpolation, SNAPHU unwrapping, and geocoding
# for NISAR LA/LB interferograms.
#
# The local programs used by this driver are:
#   snaphu_interp_fast.csh
#   nearest_grid_c_exact.py
#
# Modified by : Xin Wang
# Affiliation : University of Science and Technology of China (USTC)
#               Hefei, China
# Updated     : 2026-07-29
#
# Usage:
#   ./run6_unwrap_interp_geocode_LA_LB.sh \
#       CORR_THRESHOLD MAX_DISCONTINUITY
#
# Optional radar-coordinate subset:
#   ./run6_unwrap_interp_geocode_LA_LB.sh \
#       CORR_THRESHOLD MAX_DISCONTINUITY RNG0/RNGF/AZI0/AZIF
#
# Example:
#   ./run6_unwrap_interp_geocode_LA_LB.sh 0.1 0
#

set -euo pipefail

export LC_ALL=C
export LANG=C
export LANGUAGE=C

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
    pwd -P
)"
ROOT_DIR="$SCRIPT_DIR"
SNAPHU_INTERP="$SCRIPT_DIR/snaphu_interp_fast.csh"
EXACT_INTERP="$SCRIPT_DIR/nearest_grid_c_exact.py"

usage()
{
    cat <<'EOF'

============================================================
Run 6: fast interpolation unwrap + geocode for NISAR LA/LB

Usage:

  ./run6_unwrap_interp_geocode_LA_LB.sh \
      CORR_THRESHOLD MAX_DISCONTINUITY

Optional radar-coordinate subset:

  ./run6_unwrap_interp_geocode_LA_LB.sh \
      CORR_THRESHOLD MAX_DISCONTINUITY RNG0/RNGF/AZI0/AZIF

Example:

  ./run6_unwrap_interp_geocode_LA_LB.sh 0.1 0

Arguments:

  CORR_THRESHOLD
      Pixels below this correlation value are excluded before
      nearest-neighbour interpolation. Must be between 0 and 1.

  MAX_DISCONTINUITY
      0  : continuous deformation mode.
      >0 : allow phase discontinuities.

  RNG0/RNGF/AZI0/AZIF
      Optional radar-coordinate processing region.

Processing:

  LA and LB are processed in parallel. For each channel:

    1. Validate phasefilt.grd, corr.grd, mask.grd and trans.dat.
    2. Call the local snaphu_interp_fast.csh.
    3. Fill masked phase pixels using local nearest_grid_c_exact.py.
    4. Run SNAPHU and verify the radar-coordinate products.
    5. Run geocode.csh and verify unwrap_ll.grd.

Main outputs in each LA/LB interferogram directory:

  unwrap.grd
  unwrap.pdf
  conncomp.grd
  phasefilt_interp.grd
  unwrap_ll.grd
  los_ll.grd
  phasefilt_ll.grd
  phase_mask_ll.grd

Python:

  By default, python3 is used. To select a Conda Python:

    export NEAREST_GRID_PYTHON="$(which python)"

  Required packages: numpy scipy netCDF4

============================================================

EOF
}

die()
{
    echo "[ERROR] $*" >&2
    exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ $# -lt 2 || $# -gt 3 ]]; then
    usage
    exit 1
fi

CORR_THRESHOLD="$1"
MAX_DISCONTINUITY="$2"
RADAR_REGION="${3:-}"

[[ "$CORR_THRESHOLD" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] ||
    die "Invalid correlation threshold: $CORR_THRESHOLD"

awk -v value="$CORR_THRESHOLD" \
    'BEGIN {exit !(value >= 0 && value <= 1)}' ||
    die "Correlation threshold must be between 0 and 1."

[[ "$MAX_DISCONTINUITY" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] ||
    die "Invalid maximum discontinuity: $MAX_DISCONTINUITY"

if [[ -n "$RADAR_REGION" ]]; then
    [[ "$RADAR_REGION" =~ ^[0-9]+([.][0-9]+)?/[0-9]+([.][0-9]+)?/[0-9]+([.][0-9]+)?/[0-9]+([.][0-9]+)?$ ]] ||
        die "Invalid radar region: $RADAR_REGION"
fi

[[ -s "$SNAPHU_INTERP" ]] ||
    die "Missing local script: $SNAPHU_INTERP"
[[ -s "$EXACT_INTERP" ]] ||
    die "Missing local script: $EXACT_INTERP"

PYTHON_CMD="${NEAREST_GRID_PYTHON:-python3}"
command -v "$PYTHON_CMD" >/dev/null 2>&1 ||
    die "Python command not found: $PYTHON_CMD"

"$PYTHON_CMD" -c 'import numpy, scipy, netCDF4' >/dev/null 2>&1 ||
    die "$PYTHON_CMD must provide numpy, scipy, and netCDF4"

export NEAREST_GRID_PYTHON="$PYTHON_CMD"

for command_name in \
    gmt \
    snaphu \
    gmtsar_sharedir.csh \
    geocode.csh \
    tcsh
do
    command -v "$command_name" >/dev/null 2>&1 ||
        die "Command not found: $command_name"
done

[[ -d "$ROOT_DIR/LA/intf" ]] || die "Missing $ROOT_DIR/LA/intf/"
[[ -d "$ROOT_DIR/LB/intf" ]] || die "Missing $ROOT_DIR/LB/intf/"

chmod +x "$SNAPHU_INTERP" "$EXACT_INTERP"

echo "============================================================"
echo "Run 6: fast interpolation unwrap + geocode"
echo "Root              : $ROOT_DIR"
echo "Threshold         : $CORR_THRESHOLD"
echo "Max discontinuity : $MAX_DISCONTINUITY"
echo "Radar region      : ${RADAR_REGION:-complete interferogram}"
echo "SNAPHU interp     : $SNAPHU_INTERP"
echo "Nearest-grid code : $EXACT_INTERP"
echo "Python            : $PYTHON_CMD"
echo "Geocode           : $(command -v geocode.csh)"
echo "============================================================"

find_intf()
{
    local channel="$1"
    local intf_dirs=()

    while IFS= read -r intf_dir; do
        intf_dirs+=("$intf_dir")
    done < <(
        find "$ROOT_DIR/$channel/intf" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -name '20*' |
            sort
    )

    if [[ ${#intf_dirs[@]} -eq 0 ]]; then
        echo "[$channel] No interferogram directory found." >&2
        return 1
    fi

    if [[ ${#intf_dirs[@]} -gt 1 ]]; then
        echo "[$channel] More than one interferogram directory found:" >&2
        printf '  %s\n' "${intf_dirs[@]}" >&2
        return 1
    fi

    printf '%s\n' "${intf_dirs[0]}"
}

process_channel()
{
    local channel="$1"
    local intf_dir
    local snaphu_args

    intf_dir="$(find_intf "$channel")"
    cd "$intf_dir"

    echo
    echo "============================================================"
    echo "[$channel] START"
    echo "[$channel] Directory: $intf_dir"
    echo "============================================================"

    for input_file in \
        phasefilt.grd \
        corr.grd \
        mask.grd \
        trans.dat
    do
        [[ -s "$input_file" ]] ||
            die "$channel: missing $intf_dir/$input_file"
    done

    if [[ -s landmask_ra.grd ]]; then
        echo "[$channel] Land mask: landmask_ra.grd"
    else
        echo "[$channel] Land mask: not present; processing without it"
    fi

    echo "[$channel] Removing previous unwrap/geocode products"

    rm -f \
        unwrap.grd \
        unwrap.pdf \
        unwrap_ll.grd \
        unwrap_mask.grd \
        unwrap_mask_ll.grd \
        los.grd \
        los_ll.grd \
        unwrap.cpt \
        unwrap.ps \
        unwrap_grad.grd \
        conncomp.grd \
        conncomp.out \
        phasefilt_interp.grd

    rm -f \
        tmp.grd \
        tmp2.grd \
        corr_tmp.grd \
        phase_tmp.grd \
        unwrap.out \
        phase.in \
        corr.in \
        mask_patch.grd \
        corr_patch.grd \
        corr_cut.grd \
        phase_patch.grd \
        landmask_ra_patch.grd \
        mask_def_patch.grd \
        mask2_patch.grd \
        mask3.grd \
        mask3.out \
        snaphu.conf.brief

    snaphu_args=(
        "$CORR_THRESHOLD"
        "$MAX_DISCONTINUITY"
    )
    if [[ -n "$RADAR_REGION" ]]; then
        snaphu_args+=("$RADAR_REGION")
    fi

    echo "[$channel] Fast interpolation + SNAPHU start"
    "$SNAPHU_INTERP" "${snaphu_args[@]}"

    [[ -s unwrap.grd ]] ||
        die "$channel: unwrap.grd was not generated"
    [[ -s unwrap.pdf ]] ||
        die "$channel: unwrap.pdf was not generated"
    [[ -s conncomp.grd ]] ||
        die "$channel: conncomp.grd was not generated"
    [[ -e phasefilt_interp.grd ]] ||
        die "$channel: phasefilt_interp.grd was not generated"

    echo "[$channel] Fast interpolation + SNAPHU finished"
    echo "[$channel] Geocode start"

    geocode.csh "$CORR_THRESHOLD"

    [[ -s unwrap_ll.grd ]] ||
        die "$channel: unwrap_ll.grd was not generated"

    echo "[$channel] Geocode finished"
    echo "============================================================"
    echo "[$channel] DONE"
    echo "============================================================"
}

process_channel LA > "$ROOT_DIR/run6_interp_LA.log" 2>&1 &
PID_LA=$!

process_channel LB > "$ROOT_DIR/run6_interp_LB.log" 2>&1 &
PID_LB=$!

echo "LA PID: $PID_LA"
echo "LB PID: $PID_LB"

FAIL=0
wait "$PID_LA" || FAIL=1
wait "$PID_LB" || FAIL=1

if [[ "$FAIL" -ne 0 ]]; then
    echo
    echo "============================================================"
    echo "[FAILED] Run 6 fast interpolation unwrap failed."
    echo "Check:"
    echo "  $ROOT_DIR/run6_interp_LA.log"
    echo "  $ROOT_DIR/run6_interp_LB.log"
    echo "============================================================"
    exit 1
fi

echo
echo "============================================================"
echo "[DONE] Run 6 fast interpolation unwrap + geocode completed."
echo
echo "Main outputs:"
echo "  LA/intf/*/unwrap.grd"
echo "  LA/intf/*/unwrap_ll.grd"
echo "  LA/intf/*/conncomp.grd"
echo "  LA/intf/*/phasefilt_interp.grd"
echo "  LB/intf/*/unwrap.grd"
echo "  LB/intf/*/unwrap_ll.grd"
echo "  LB/intf/*/conncomp.grd"
echo "  LB/intf/*/phasefilt_interp.grd"
echo
echo "Logs:"
echo "  run6_interp_LA.log"
echo "  run6_interp_LB.log"
echo "============================================================"
