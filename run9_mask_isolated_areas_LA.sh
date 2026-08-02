#!/usr/bin/env bash
#
# Run 9 (optional): manually mask isolated areas from the final
# ionosphere-corrected LA products produced by run8.
#
# The polygons in mask_island.txt are exclusion polygons:
#   outside polygon = 1   (retain)
#   polygon boundary = NaN
#   inside polygon  = NaN (remove)
#
# Original run8 grids are never overwritten.  New grids use the suffix
# "_mask" and are written in LA_iono_corrected/.
#
# Modified by : Xin Wang
# Affiliation : University of Science and Technology of China (USTC)
#               Hefei, China
# Updated     : 2026-08-02
#
# Usage:
#   ./run9_mask_isolated_areas_LA.sh
#
# Optional explicit mask file:
#   ./run9_mask_isolated_areas_LA.sh /path/to/mask_island.txt
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
RUN8_DIR="${RUN8_OUTPUT_DIR:-$PROJECT_DIR/LA_iono_corrected}"

usage()
{
    cat <<'EOF'

============================================================
Run 9: optional manual masking of isolated LA areas

Usage:

  ./run9_mask_isolated_areas_LA.sh [MASK_FILE]

Default mask file:

  LA_iono_corrected/mask_island.txt

The coordinates in mask_island.txt must be radar-grid x/y coordinates.
Each polygon encloses an area that will be removed.  Multiple polygons
must be separated by a line beginning with ">", for example:

  > island_1
  1000 50000
  1300 50000
  1300 52000
  1000 52000
  > island_2
  24000 1000
  26000 1000
  26000 3000
  24000 3000

Run8 input grids are retained.  Run9 creates new products with "_mask"
in their names, plus radar/geographic PDFs and Google Earth KML/PNG.
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

if [[ $# -gt 1 ]]; then
    usage
    exit 1
fi

for command_name in gmt proj_ra2ll.csh grd2kml.csh; do
    command -v "$command_name" >/dev/null 2>&1 ||
        die "Command not found: $command_name"
done

[[ -d "$RUN8_DIR" ]] ||
    die "Missing run8 directory: $RUN8_DIR"

if [[ $# -eq 1 ]]; then
    MASK_FILE="$1"
    if [[ ! -s "$MASK_FILE" && -s "$RUN8_DIR/$MASK_FILE" ]]; then
        MASK_FILE="$RUN8_DIR/$MASK_FILE"
    fi
else
    MASK_FILE="$RUN8_DIR/mask_island.txt"
fi

[[ -s "$MASK_FILE" ]] || {
    echo "[ERROR] Mask polygon file was not found: $MASK_FILE" >&2
    echo "Create it in radar x/y coordinates, then run this script again." >&2
    exit 1
}

MASK_FILE="$(
    cd -- "$(dirname -- "$MASK_FILE")"
    printf '%s/%s\n' "$(pwd -P)" "$(basename -- "$MASK_FILE")"
)"

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
    echo "[ERROR] More than one LA interferogram directory was found:" >&2
    printf '  %s\n' "${pair_list[@]}" >&2
    exit 1
fi

LA_DIR="${pair_list[0]}"
PAIR_NAME="$(basename "$LA_DIR")"
TRANS_DAT="$LA_DIR/trans.dat"

[[ -s "$TRANS_DAT" ]] ||
    die "Missing geocoding lookup table: $TRANS_DAT"

for input_grid in \
    phase_iono_corrected.grd \
    unwrap.grd \
    los.grd
do
    [[ -s "$RUN8_DIR/$input_grid" ]] ||
        die "Missing run8 input: $RUN8_DIR/$input_grid"
done

cd "$RUN8_DIR"

# Run8 removes its temporary trans.dat link during cleanup.  Recreate and
# retain the link here so the run9 products remain self-contained for later
# re-geocoding.  Never replace a real, non-symbolic file automatically.
if [[ -L trans.dat ]]; then
    rm -f trans.dat
elif [[ -e trans.dat ]]; then
    die "$RUN8_DIR/trans.dat exists and is not a symbolic link"
fi
ln -s "$TRANS_DAT" trans.dat
[[ -s trans.dat ]] ||
    die "Could not create the geocoding link: $RUN8_DIR/trans.dat"

echo "============================================================"
echo "NISAR LA OPTIONAL ISOLATED-AREA MASKING"
echo "Project directory : $PROJECT_DIR"
echo "Pair              : $PAIR_NAME"
echo "Run8 directory    : $RUN8_DIR"
echo "Exclusion polygons: $MASK_FILE"
echo "Mask convention   : outside=1, boundary/inside=NaN"
echo "============================================================"

# Remove only previous run9 products.  Original run8 products are retained.
rm -f \
    mask_island.grd \
    mask_island.cpt \
    mask_island.pdf \
    phase_iono_corrected_mask.grd \
    unwrap_mask.grd \
    los_mask.grd \
    phase_iono_corrected_mask_ll.grd \
    unwrap_mask_ll.grd \
    los_mask_ll.grd \
    phase_mask.cpt \
    unwrap_mask.cpt \
    los_mask.cpt \
    phase_iono_corrected_mask.pdf \
    phase_iono_corrected_mask_ll.pdf \
    unwrap_mask.pdf \
    unwrap_mask_ll.pdf \
    los_mask.pdf \
    los_mask_ll.pdf \
    masked_results_2x3.pdf \
    phase_iono_corrected_mask_ll.png \
    phase_iono_corrected_mask_ll.kml \
    unwrap_mask_ll.png \
    unwrap_mask_ll.kml \
    los_mask_ll.png \
    los_mask_ll.kml \
    run9_mask_report.txt

GRID_INC="$(gmt grdinfo -I unwrap.grd)"

echo "Creating exclusion mask on the run8 radar grid..."
gmt grdmask \
    "$MASK_FILE" \
    -Runwrap.grd \
    "$GRID_INC" \
    -N1/NaN/NaN \
    -Gmask_island.grd

[[ -s mask_island.grd ]] ||
    die "GMT did not generate mask_island.grd"

echo "Applying the exclusion mask..."
gmt grdmath \
    phase_iono_corrected.grd \
    mask_island.grd \
    MUL \
    = phase_iono_corrected_mask.grd

gmt grdmath \
    unwrap.grd \
    mask_island.grd \
    MUL \
    = unwrap_mask.grd

gmt grdmath \
    los.grd \
    mask_island.grd \
    MUL \
    = los_mask.grd

for masked_grid in \
    phase_iono_corrected_mask.grd \
    unwrap_mask.grd \
    los_mask.grd
do
    [[ -s "$masked_grid" ]] ||
        die "Masking did not generate $masked_grid"
done

echo "Geocoding the masked wrapped phase..."
proj_ra2ll.csh \
    trans.dat \
    phase_iono_corrected_mask.grd \
    phase_iono_corrected_mask_ll.grd

echo "Geocoding the masked unwrapped phase..."
proj_ra2ll.csh \
    trans.dat \
    unwrap_mask.grd \
    unwrap_mask_ll.grd

echo "Geocoding the masked LOS displacement..."
proj_ra2ll.csh \
    trans.dat \
    los_mask.grd \
    los_mask_ll.grd

for geographic_grid in \
    phase_iono_corrected_mask_ll.grd \
    unwrap_mask_ll.grd \
    los_mask_ll.grd
do
    [[ -s "$geographic_grid" ]] ||
        die "Geocoding did not generate $geographic_grid"
done

gmt grdedit \
    "-D+xrange+yazimuth+dmm+tMasked LOS displacement" \
    los_mask.grd

gmt grdedit \
    "-D+xdegree+ydegree+dmm+tMasked LOS displacement" \
    los_mask_ll.grd

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

make_symmetric_absmax_cpt()
{
    local grid="$1"
    local palette="$2"
    local output_cpt="$3"
    local grid_min
    local grid_max
    local limit
    local lower
    local step

    read -r grid_min grid_max < <(
        gmt grdinfo "$grid" -C |
            awk '{print $6, $7}'
    )

    limit="$(
        awk -v lo="$grid_min" -v hi="$grid_max" '
            BEGIN {
                if (lo < 0) lo = -lo
                if (hi < 0) hi = -hi
                value = (lo > hi ? lo : hi)
                if (!(value > 0)) value = 1
                printf "%.12g", value
            }
        '
    )"
    lower="$(awk -v x="$limit" 'BEGIN {printf "%.12g", -x}')"
    step="$(awk -v x="$limit" 'BEGIN {printf "%.12g", 2*x/100}')"

    gmt makecpt \
        -C"$palette" \
        -T"$lower/$limit/$step" \
        -Z > "$output_cpt"
}

PI="3.141592653589793"
gmt makecpt \
    -Cmatlab/jet \
    -T-"$PI"/"$PI"/0.062831853071796 \
    -Z > phase_mask.cpt

make_robust_cpt \
    unwrap_mask.grd \
    vik \
    unwrap_mask.cpt

# Use the full absolute LOS maximum at both ends of the color scale.
make_symmetric_absmax_cpt \
    los_mask.grd \
    polar \
    los_mask.cpt

gmt makecpt \
    -Cgray \
    -T0/1/1 \
    -Z > mask_island.cpt

plot_radar_grid()
{
    local grid="$1"
    local cpt="$2"
    local output_stem="$3"
    local title="$4"
    local color_label="$5"

    gmt begin "$output_stem" pdf
        gmt set \
            FONT_TITLE 15p \
            FONT_LABEL 11p \
            FONT_ANNOT_PRIMARY 9p \
            MAP_FRAME_TYPE plain \
            COLOR_NAN 150/150/150

        gmt grdimage \
            "$grid" \
            -C"$cpt" \
            -JX16c/11c \
            -Baf \
            -BWSen+t"$title"

        gmt colorbar \
            -C"$cpt" \
            -DJBC+w10c/0.3c+h+o0/0.7c \
            -Baf+l"$color_label"
    gmt end
}

plot_geographic_grid()
{
    local grid="$1"
    local cpt="$2"
    local output_stem="$3"
    local title="$4"
    local color_label="$5"

    gmt begin "$output_stem" pdf
        gmt set \
            FONT_TITLE 15p \
            FONT_LABEL 11p \
            FONT_ANNOT_PRIMARY 9p \
            MAP_FRAME_TYPE plain \
            COLOR_NAN 150/150/150

        gmt grdimage \
            "$grid" \
            -C"$cpt" \
            -JM16c \
            -Baf \
            -BWSen+t"$title"

        gmt colorbar \
            -C"$cpt" \
            -DJBC+w10c/0.3c+h+o0/0.7c \
            -Baf+l"$color_label"
    gmt end
}

echo "Creating the manual exclusion-mask figure..."
gmt begin mask_island pdf
    gmt set \
        FONT_TITLE 15p \
        FONT_LABEL 11p \
        FONT_ANNOT_PRIMARY 9p \
        MAP_FRAME_TYPE plain \
        COLOR_NAN 150/150/150

    gmt grdimage \
        mask_island.grd \
        -Cmask_island.cpt \
        -JX16c/11c \
        -Baf \
        -BWSen+t"Manual isolated-area exclusion mask: $PAIR_NAME"

    gmt plot \
        "$MASK_FILE" \
        -W1.2p,red
gmt end

echo "Creating radar-coordinate masked figures..."
plot_radar_grid \
    phase_iono_corrected_mask.grd \
    phase_mask.cpt \
    phase_iono_corrected_mask \
    "NISAR LA masked corrected wrapped phase: $PAIR_NAME" \
    "Wrapped phase (rad)"

plot_radar_grid \
    unwrap_mask.grd \
    unwrap_mask.cpt \
    unwrap_mask \
    "NISAR LA masked corrected unwrapped phase: $PAIR_NAME" \
    "Unwrapped phase (rad)"

plot_radar_grid \
    los_mask.grd \
    los_mask.cpt \
    los_mask \
    "NISAR LA masked ionosphere-corrected LOS: $PAIR_NAME" \
    "LOS displacement (mm)"

echo "Creating geographic-coordinate masked figures..."
plot_geographic_grid \
    phase_iono_corrected_mask_ll.grd \
    phase_mask.cpt \
    phase_iono_corrected_mask_ll \
    "NISAR LA masked corrected wrapped phase: $PAIR_NAME" \
    "Wrapped phase (rad)"

plot_geographic_grid \
    unwrap_mask_ll.grd \
    unwrap_mask.cpt \
    unwrap_mask_ll \
    "NISAR LA masked corrected unwrapped phase: $PAIR_NAME" \
    "Unwrapped phase (rad)"

plot_geographic_grid \
    los_mask_ll.grd \
    los_mask.cpt \
    los_mask_ll \
    "NISAR LA masked ionosphere-corrected LOS: $PAIR_NAME" \
    "LOS displacement (mm)"

echo "Creating the radar/geographic 2x3 summary figure..."
gmt begin masked_results_2x3 pdf
    gmt set \
        FONT_TITLE 13p \
        FONT_LABEL 9p \
        FONT_ANNOT_PRIMARY 7p \
        MAP_FRAME_TYPE plain \
        COLOR_NAN 150/150/150

    gmt subplot begin 2x3 \
        -Fs10c/7c \
        -M0.35c/1.1c \
        -T"NISAR LA manually masked final products: $PAIR_NAME"

        gmt subplot set 0,0
        gmt grdimage phase_iono_corrected_mask.grd -Cphase_mask.cpt -JX? -Baf -BWSen+t"(a) Wrapped phase, radar"
        gmt colorbar -Cphase_mask.cpt -DJBC+w7c/0.22c+h+o0/0.5c -Bxa3.14159265359+l"rad"

        gmt subplot set 0,1
        gmt grdimage unwrap_mask.grd -Cunwrap_mask.cpt -JX? -Baf -BWSen+t"(b) Unwrapped phase, radar"
        gmt colorbar -Cunwrap_mask.cpt -DJBC+w7c/0.22c+h+o0/0.5c -Baf+l"rad"

        gmt subplot set 0,2
        gmt grdimage los_mask.grd -Clos_mask.cpt -JX? -Baf -BWSen+t"(c) LOS, radar"
        gmt colorbar -Clos_mask.cpt -DJBC+w7c/0.22c+h+o0/0.5c -Baf+l"mm"

        gmt subplot set 1,0
        gmt grdimage phase_iono_corrected_mask_ll.grd -Cphase_mask.cpt -JM? -Baf -BWSen+t"(d) Wrapped phase, geographic"
        gmt colorbar -Cphase_mask.cpt -DJBC+w7c/0.22c+h+o0/0.5c -Bxa3.14159265359+l"rad"

        gmt subplot set 1,1
        gmt grdimage unwrap_mask_ll.grd -Cunwrap_mask.cpt -JM? -Baf -BWSen+t"(e) Unwrapped phase, geographic"
        gmt colorbar -Cunwrap_mask.cpt -DJBC+w7c/0.22c+h+o0/0.5c -Baf+l"rad"

        gmt subplot set 1,2
        gmt grdimage los_mask_ll.grd -Clos_mask.cpt -JM? -Baf -BWSen+t"(f) LOS, geographic"
        gmt colorbar -Clos_mask.cpt -DJBC+w7c/0.22c+h+o0/0.5c -Baf+l"mm"

    gmt subplot end
gmt end

echo "Creating Google Earth KML/PNG products..."
grd2kml.csh phase_iono_corrected_mask_ll phase_mask.cpt
grd2kml.csh unwrap_mask_ll unwrap_mask.cpt
grd2kml.csh los_mask_ll los_mask.cpt

for google_earth_stem in \
    phase_iono_corrected_mask_ll \
    unwrap_mask_ll \
    los_mask_ll
do
    [[ -s "$google_earth_stem.kml" ]] ||
        die "Google Earth output was not generated: $google_earth_stem.kml"
    [[ -s "$google_earth_stem.png" ]] ||
        die "Google Earth output was not generated: $google_earth_stem.png"
done

echo
echo "============================================================"
echo "Run 9 completed for $PAIR_NAME"
echo "Output directory: $RUN8_DIR"
echo
echo "Mask:"
echo "  mask_island.grd"
echo "  mask_island.pdf"
echo "  trans.dat -> $TRANS_DAT"
echo
echo "Radar-coordinate masked grids/PDFs:"
echo "  phase_iono_corrected_mask.grd/.pdf"
echo "  unwrap_mask.grd/.pdf"
echo "  los_mask.grd/.pdf"
echo
echo "Geographic masked grids/PDFs:"
echo "  phase_iono_corrected_mask_ll.grd/.pdf"
echo "  unwrap_mask_ll.grd/.pdf"
echo "  los_mask_ll.grd/.pdf"
echo
echo "Google Earth KML/PNG:"
echo "  phase_iono_corrected_mask_ll.kml/.png"
echo "  unwrap_mask_ll.kml/.png"
echo "  los_mask_ll.kml/.png"
echo
echo "Summary:"
echo "  masked_results_2x3.pdf"
echo "============================================================"
