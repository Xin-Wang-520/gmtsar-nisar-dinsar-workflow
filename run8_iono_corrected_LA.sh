#!/usr/bin/env bash
#
# Run 8: produce the final ionosphere-corrected LA unwrapped phase
# and LOS displacement in radar and geographic coordinates.
#
# Processing:
#   phase_LA_after.grd
#       -> SNAPHU
#       -> unwrap.grd
#       -> LOS conversion and geographic projection
#
# No additional 2*pi reference alignment is applied. The direct SNAPHU
# output is retained as the final ionosphere-corrected unwrapped phase.
#
# Modified by : Xin Wang
# Affiliation : University of Science and Technology of China (USTC)
#               Hefei, China
# Updated     : 2026-07-29
#
# Usage:
#   ./run8_iono_corrected_LA.sh \
#       CORR_THRESHOLD MAX_DISCONTINUITY
#
# Example:
#   ./run8_iono_corrected_LA.sh 0.1 0
#

set -euo pipefail

export LC_ALL=C
export LANG=C
export LANGUAGE=C

SCRIPT_DIR="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
    pwd -P
)"
PROJECT_DIR="$SCRIPT_DIR"
RUN7_DIR="${IONO_OUTPUT_DIR:-$PROJECT_DIR/iono_correction}"
RUN8_DIR="${RUN8_OUTPUT_DIR:-$PROJECT_DIR/LA_iono_corrected}"
SNAPHU_INTERP="$PROJECT_DIR/snaphu_interp_fast.csh"
EXACT_INTERP="$PROJECT_DIR/nearest_grid_c_exact.py"

usage()
{
    cat <<'EOF'

============================================================
Run 8: final ionosphere-corrected LA products

Usage:

  ./run8_iono_corrected_LA.sh \
      CORR_THRESHOLD MAX_DISCONTINUITY

Example:

  ./run8_iono_corrected_LA.sh 0.1 0

Input:

  iono_correction/phase_LA_after.grd
      Run7 ionosphere-corrected LA phase wrapped to [-pi, pi].

Processing:

  1. Re-unwrap phase_LA_after.grd with fast interpolation + SNAPHU.
  2. Retain the direct SNAPHU result as unwrap.grd.
  3. Convert unwrap.grd to LOS displacement in millimetres.
  4. Geocode the corrected wrapped phase, unwrapped phase, and LOS.
  5. Create radar-coordinate and geographic-coordinate figures.

Output directory:

  LA_iono_corrected/

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

if [[ $# -ne 2 ]]; then
    usage
    exit 1
fi

CORR_THRESHOLD="$1"
MAX_DISCONTINUITY="$2"

[[ "$CORR_THRESHOLD" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] ||
    die "Invalid correlation threshold: $CORR_THRESHOLD"

awk -v value="$CORR_THRESHOLD" \
    'BEGIN {exit !(value >= 0 && value <= 1)}' ||
    die "Correlation threshold must be between 0 and 1."

[[ "$MAX_DISCONTINUITY" =~ ^([0-9]+([.][0-9]*)?|[.][0-9]+)$ ]] ||
    die "Invalid maximum discontinuity: $MAX_DISCONTINUITY"

for required_file in \
    "$SNAPHU_INTERP" \
    "$EXACT_INTERP" \
    "$RUN7_DIR/phase_LA_after.grd"
do
    [[ -s "$required_file" ]] ||
        die "Missing required file: $required_file"
done

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
    proj_ra2ll.csh \
    grd2kml.csh \
    tcsh
do
    command -v "$command_name" >/dev/null 2>&1 ||
        die "Command not found: $command_name"
done

[[ -d "$PROJECT_DIR/LA/intf" ]] ||
    die "Missing directory: $PROJECT_DIR/LA/intf"

pair_list=()
while IFS= read -r pair_dir; do
    pair_list+=("$pair_dir")
done < <(
    find "$PROJECT_DIR/LA/intf" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -name '20*' |
        sort
)

if [[ ${#pair_list[@]} -eq 0 ]]; then
    die "No LA interferogram directory was found."
fi

if [[ ${#pair_list[@]} -gt 1 ]]; then
    echo "ERROR: More than one LA interferogram directory was found:" >&2
    printf '  %s\n' "${pair_list[@]}" >&2
    exit 1
fi

LA_DIR="${pair_list[0]}"
PAIR_NAME="$(basename "$LA_DIR")"

for input_file in corr.grd mask.grd trans.dat; do
    [[ -s "$LA_DIR/$input_file" ]] ||
        die "Missing LA input: $LA_DIR/$input_file"
done

prm_list=()
while IFS= read -r prm_file; do
    prm_list+=("$prm_file")
done < <(
    find "$LA_DIR" \
        -maxdepth 1 \
        -type f \
        -name 'NSR_*A.PRM' |
        sort
)

if [[ ${#prm_list[@]} -eq 0 ]]; then
    die "No NSR_*A.PRM file was found in $LA_DIR"
fi

# Use the earlier acquisition PRM, consistent with run7.
MASTER_PRM="${prm_list[0]}"
RADAR_WAVELENGTH="$(
    awk '$1 == "radar_wavelength" {print $3; exit}' "$MASTER_PRM"
)"

if ! awk -v wavelength="$RADAR_WAVELENGTH" \
    'BEGIN {exit !(wavelength > 0)}'
then
    die "Could not read radar_wavelength from $MASTER_PRM"
fi

mkdir -p "$RUN8_DIR"
cd "$RUN8_DIR"

echo "============================================================"
echo "NISAR LA CORRECTED-PHASE RE-UNWRAPPING"
echo "Project           : $PROJECT_DIR"
echo "Pair              : $PAIR_NAME"
echo "Run7 wrapped input: $RUN7_DIR/phase_LA_after.grd"
echo "LA master PRM     : $MASTER_PRM"
echo "Radar wavelength  : $RADAR_WAVELENGTH m"
echo "Correlation limit : $CORR_THRESHOLD"
echo "Max discontinuity : $MAX_DISCONTINUITY"
echo "Output directory  : $RUN8_DIR"
echo "============================================================"

# Remove only products created inside the dedicated run8 directory.
rm -f \
    phase_iono_corrected.grd \
    phase_iono_corrected_ll.grd \
    phasefilt.grd \
    corr.grd \
    mask.grd \
    landmask_ra.grd \
    mask_def.grd \
    trans.dat \
    master_A.PRM \
    phasefilt_interp.grd \
    unwrap.grd \
    unwrap.pdf \
    unwrap.cpt \
    unwrap.ps \
    unwrap_grad.grd \
    conncomp.grd \
    conncomp.out \
    mask_patch.grd \
    corr_patch.grd \
    corr_cut.grd \
    phase_patch.grd \
    landmask_ra_patch.grd \
    mask_def_patch.grd \
    mask2_patch.grd \
    mask3.grd \
    mask3.out \
    corr_tmp.grd \
    phase_tmp.grd \
    tmp.grd \
    tmp2.grd \
    phase.in \
    corr.in \
    unwrap.out \
    snaphu.conf.brief \
    unwrap_ll.grd \
    los.grd \
    los_ll.grd \
    los.cpt \
    phase.cpt \
    phase_iono_corrected.png \
    phase_iono_corrected.pdf \
    phase_iono_corrected_ll.png \
    phase_iono_corrected_ll.pdf \
    phase_iono_corrected_ll.kml \
    unwrap.png \
    unwrap_ll.png \
    unwrap_ll.pdf \
    unwrap_ll.kml \
    los.png \
    los.pdf \
    los_ll.png \
    los_ll.pdf \
    los_ll.kml \
    result_2x2.png \
    result_2x2.pdf \
    report.txt

ln -s "$RUN7_DIR/phase_LA_after.grd" phase_iono_corrected.grd
ln -s phase_iono_corrected.grd phasefilt.grd
ln -s "$LA_DIR/corr.grd" corr.grd
ln -s "$LA_DIR/mask.grd" mask.grd
ln -s "$LA_DIR/trans.dat" trans.dat
ln -s "$MASTER_PRM" master_A.PRM

if [[ -s "$LA_DIR/landmask_ra.grd" ]]; then
    ln -s "$LA_DIR/landmask_ra.grd" landmask_ra.grd
fi

if [[ -s "$LA_DIR/mask_def.grd" ]]; then
    ln -s "$LA_DIR/mask_def.grd" mask_def.grd
fi

echo "Re-unwrapping phase_LA_after.grd..."
"$SNAPHU_INTERP" "$CORR_THRESHOLD" "$MAX_DISCONTINUITY"

[[ -s unwrap.grd ]] ||
    die "SNAPHU did not generate unwrap.grd"
[[ -s conncomp.grd ]] ||
    die "SNAPHU did not generate conncomp.grd"

echo "Converting re-unwrapped phase to LOS displacement..."

# GMTSAR convention:
#   LOS (mm) = unwrapped phase * wavelength * [-1000/(4*pi)]
#            ~= unwrapped phase * wavelength * -79.58
gmt grdmath \
    unwrap.grd \
    "$RADAR_WAVELENGTH" MUL \
    -79.58 MUL \
    = los.grd

gmt grdedit \
    "-D+xrange+yazimuth+dmm+tLOS displacement" \
    los.grd

echo "Geocoding ionosphere-corrected wrapped phase..."
proj_ra2ll.csh \
    trans.dat \
    phase_iono_corrected.grd \
    phase_iono_corrected_ll.grd

echo "Geocoding re-unwrapped phase..."
proj_ra2ll.csh \
    trans.dat \
    unwrap.grd \
    unwrap_ll.grd

echo "Geocoding LOS displacement..."
proj_ra2ll.csh \
    trans.dat \
    los.grd \
    los_ll.grd

for output_grid in \
    phase_iono_corrected_ll.grd \
    unwrap_ll.grd \
    los_ll.grd
do
    [[ -s "$output_grid" ]] ||
        die "Geocoding did not generate $output_grid"
done

gmt grdedit \
    "-D+xdegree+ydegree+dmm+tLOS displacement" \
    los_ll.grd

make_robust_cpt()
{
    local grid="$1"
    local palette="$2"
    local output_cpt="$3"
    local mean
    local std
    local lower
    local upper
    local step

    read -r mean std < <(
        gmt grdinfo "$grid" -C -L2 |
            awk '{print $12, $13}'
    )

    lower="$(
        awk -v center="$mean" -v spread="$std" \
            'BEGIN {printf "%.12g", center - 2*spread}'
    )"
    upper="$(
        awk -v center="$mean" -v spread="$std" \
            'BEGIN {printf "%.12g", center + 2*spread}'
    )"
    step="$(
        awk -v lo="$lower" -v hi="$upper" '
            BEGIN {
                value = (hi - lo) / 100
                if (!(value > 0)) value = 0.01
                printf "%.12g", value
            }
        '
    )"

    gmt makecpt \
        -C"$palette" \
        -T"$lower/$upper/$step" \
        -Z > "$output_cpt"
}

make_robust_cpt \
    unwrap.grd \
    vik \
    unwrap.cpt

make_robust_cpt \
    los.grd \
    polar \
    los.cpt

PI="3.141592653589793"
gmt makecpt \
    -Cmatlab/jet \
    -T-"$PI"/"$PI"/0.062831853071796 \
    -Z > phase.cpt

echo "Creating radar-coordinate corrected wrapped-phase figure..."
gmt begin phase_iono_corrected pdf
    gmt set \
        FONT_TITLE 15p \
        FONT_LABEL 11p \
        FONT_ANNOT_PRIMARY 9p \
        MAP_FRAME_TYPE plain \
        COLOR_NAN 150/150/150

    gmt grdimage \
        phase_iono_corrected.grd \
        -Cphase.cpt \
        -JX16c/11c \
        -Baf \
        -BWSen+t"NISAR LA ionosphere-corrected wrapped phase: $PAIR_NAME"

    gmt colorbar \
        -Cphase.cpt \
        -DJBC+w10c/0.3c+h+o0/0.7c \
        -Bxa3.14159265359+l"Wrapped phase (rad)"
gmt end

echo "Creating geographic corrected wrapped-phase figure..."
gmt begin phase_iono_corrected_ll pdf
    gmt set \
        FONT_TITLE 15p \
        FONT_LABEL 11p \
        FONT_ANNOT_PRIMARY 9p \
        MAP_FRAME_TYPE plain \
        COLOR_NAN 150/150/150

    gmt grdimage \
        phase_iono_corrected_ll.grd \
        -Cphase.cpt \
        -JM16c \
        -Baf \
        -BWSen+t"NISAR LA ionosphere-corrected wrapped phase: $PAIR_NAME"

    gmt colorbar \
        -Cphase.cpt \
        -DJBC+w10c/0.3c+h+o0/0.7c \
        -Bxa3.14159265359+l"Wrapped phase (rad)"
gmt end

echo "Creating radar-coordinate re-unwrapped phase figure..."
gmt begin unwrap pdf
    gmt set \
        FONT_TITLE 15p \
        FONT_LABEL 11p \
        FONT_ANNOT_PRIMARY 9p \
        MAP_FRAME_TYPE plain \
        COLOR_NAN 150/150/150

    gmt grdimage \
        unwrap.grd \
        -Cunwrap.cpt \
        -JX16c/11c \
        -Baf \
        -BWSen+t"NISAR LA corrected and re-unwrapped phase: $PAIR_NAME"

    gmt colorbar \
        -Cunwrap.cpt \
        -DJBC+w10c/0.3c+h+o0/0.7c \
        -Baf+l"Unwrapped phase (rad)"
gmt end

echo "Creating geographic re-unwrapped phase figure..."
gmt begin unwrap_ll pdf
    gmt set \
        FONT_TITLE 15p \
        FONT_LABEL 11p \
        FONT_ANNOT_PRIMARY 9p \
        MAP_FRAME_TYPE plain \
        COLOR_NAN 150/150/150

    gmt grdimage \
        unwrap_ll.grd \
        -Cunwrap.cpt \
        -JM16c \
        -Baf \
        -BWSen+t"NISAR LA corrected re-unwrapped phase: $PAIR_NAME"

    gmt colorbar \
        -Cunwrap.cpt \
        -DJBC+w10c/0.3c+h+o0/0.7c \
        -Baf+l"Unwrapped phase (rad)"
gmt end

echo "Creating radar-coordinate LOS figure..."
gmt begin los pdf
    gmt set \
        FONT_TITLE 15p \
        FONT_LABEL 11p \
        FONT_ANNOT_PRIMARY 9p \
        MAP_FRAME_TYPE plain \
        COLOR_NAN 150/150/150

    gmt grdimage \
        los.grd \
        -Clos.cpt \
        -JX16c/11c \
        -Baf \
        -BWSen+t"NISAR LA ionosphere-corrected LOS: $PAIR_NAME"

    gmt colorbar \
        -Clos.cpt \
        -DJBC+w10c/0.3c+h+o0/0.7c \
        -Baf+l"LOS displacement (mm)"
gmt end

echo "Creating geographic LOS figure..."
gmt begin los_ll pdf
    gmt set \
        FONT_TITLE 15p \
        FONT_LABEL 11p \
        FONT_ANNOT_PRIMARY 9p \
        MAP_FRAME_TYPE plain \
        COLOR_NAN 150/150/150

    gmt grdimage \
        los_ll.grd \
        -Clos.cpt \
        -JM16c \
        -Baf \
        -BWSen+t"NISAR LA ionosphere-corrected LOS: $PAIR_NAME"

    gmt colorbar \
        -Clos.cpt \
        -DJBC+w10c/0.3c+h+o0/0.7c \
        -Baf+l"LOS displacement (mm)"
gmt end

echo "Creating run8 2x2 result figure..."
gmt begin result_2x2 pdf
    gmt set \
        FONT_TITLE 14p \
        FONT_LABEL 10p \
        FONT_ANNOT_PRIMARY 8p \
        MAP_FRAME_TYPE plain \
        COLOR_NAN 150/150/150

    gmt subplot begin 2x2 \
        -Fs12c/8c \
        -M0.4c/1.2c \
        -T"NISAR LA corrected phase re-unwrapping and LOS: $PAIR_NAME"

        gmt subplot set 0,0
        gmt grdimage \
            phase_iono_corrected.grd \
            -Cphase.cpt \
            -JX? \
            -Baf \
            -BWSen+t"(a) Run7 corrected wrapped phase"
        gmt colorbar \
            -Cphase.cpt \
            -DJBC+w8c/0.25c+h+o0/0.55c \
            -Bxa3.14159265359+l"Wrapped phase (rad)"

        gmt subplot set 0,1
        gmt grdimage \
            unwrap.grd \
            -Cunwrap.cpt \
            -JX? \
            -Baf \
            -BWSen+t"(b) Re-unwrapped phase"
        gmt colorbar \
            -Cunwrap.cpt \
            -DJBC+w8c/0.25c+h+o0/0.55c \
            -Baf+l"Unwrapped phase (rad)"

        gmt subplot set 1,0
        gmt grdimage \
            los.grd \
            -Clos.cpt \
            -JX? \
            -Baf \
            -BWSen+t"(c) LOS in radar coordinates"
        gmt colorbar \
            -Clos.cpt \
            -DJBC+w8c/0.25c+h+o0/0.55c \
            -Baf+l"LOS displacement (mm)"

        gmt subplot set 1,1
        gmt grdimage \
            los_ll.grd \
            -Clos.cpt \
            -JM? \
            -Baf \
            -BWSen+t"(d) LOS in geographic coordinates"
        gmt colorbar \
            -Clos.cpt \
            -DJBC+w8c/0.25c+h+o0/0.55c \
            -Baf+l"LOS displacement (mm)"

    gmt subplot end
gmt end

echo "Creating Google Earth KML/PNG products..."
grd2kml.csh phase_iono_corrected_ll phase.cpt
grd2kml.csh unwrap_ll unwrap.cpt
grd2kml.csh los_ll los.cpt

for google_earth_stem in \
    phase_iono_corrected_ll \
    unwrap_ll \
    los_ll
do
    [[ -s "$google_earth_stem.kml" ]] ||
        die "Google Earth output was not generated: $google_earth_stem.kml"
    [[ -s "$google_earth_stem.png" ]] ||
        die "Google Earth output was not generated: $google_earth_stem.png"
done

grid_stat_line()
{
    local label="$1"
    local grid="$2"

    gmt grdinfo "$grid" -C -L2 |
        awk -v label="$label" '
            {
                printf "%-34s %12.5g %12.5g %12.5g %12.5g %12.5g\n",
                    label, $6, $7, $12, $13, $14
            }
        '
}

REPORT="$RUN8_DIR/report.txt"
{
    echo "NISAR LA corrected phase re-unwrapping and LOS"
    echo "================================================"
    echo "Pair                 : $PAIR_NAME"
    echo "Correlation threshold: $CORR_THRESHOLD"
    echo "Maximum discontinuity: $MAX_DISCONTINUITY"
    echo "Interpolation radius : 300 pixels"
    echo "Radar wavelength     : $RADAR_WAVELENGTH m"
    echo "Phase reference      : direct SNAPHU output; no 2pi alignment"
    echo "LOS reference        : relative LOS; inherits SNAPHU phase constant"
    echo
    printf "%-34s %12s %12s %12s %12s %12s\n" \
        "grid" "minimum" "maximum" "mean" "std" "RMS"
    grid_stat_line \
        "corrected wrapped phase" \
        phase_iono_corrected.grd
    grid_stat_line \
        "corrected re-unwrapped phase" \
        unwrap.grd
    grid_stat_line \
        "LOS radar coordinates (mm)" \
        los.grd
    grid_stat_line \
        "LOS geographic coordinates (mm)" \
        los_ll.grd
} > "$REPORT"

# Remove internal links and temporary interpolation products so the final
# directory contains only the corrected phase, LOS, figures, and report.
rm -f \
    phasefilt.grd \
    corr.grd \
    mask.grd \
    landmask_ra.grd \
    mask_def.grd \
    trans.dat \
    master_A.PRM \
    phasefilt_interp.grd \
    phase_tmp.grd \
    corr_tmp.grd \
    mask_patch.grd \
    corr_patch.grd \
    corr_cut.grd \
    phase_patch.grd \
    landmask_ra_patch.grd \
    mask_def_patch.grd \
    mask2_patch.grd \
    mask3.grd \
    mask3.out \
    tmp.grd \
    tmp2.grd \
    phase.in \
    corr.in \
    unwrap.out \
    conncomp.out \
    snaphu.conf.brief

echo
echo "============================================================"
echo "Run 8 completed."
echo "Output directory:"
echo "  $RUN8_DIR"
echo
echo "Final phase:"
echo "  phase_iono_corrected.grd"
echo "  phase_iono_corrected_ll.grd"
echo "  unwrap.grd"
echo "  unwrap_ll.grd"
echo
echo "Final LOS:"
echo "  los.grd"
echo "  los_ll.grd"
echo
echo "Figures:"
echo "  phase_iono_corrected.pdf"
echo "  phase_iono_corrected_ll.pdf"
echo "  unwrap.pdf"
echo "  unwrap_ll.pdf"
echo "  los.pdf"
echo "  los_ll.pdf"
echo "  result_2x2.pdf"
echo
echo "Google Earth:"
echo "  phase_iono_corrected_ll.kml/.png"
echo "  unwrap_ll.kml/.png"
echo "  los_ll.kml/.png"
echo
echo "Report:"
echo "  report.txt"
echo "============================================================"
cat "$REPORT"
