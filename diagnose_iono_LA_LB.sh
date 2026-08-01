#!/usr/bin/env bash
#
# Read-only diagnostic test for the LA/LB split-spectrum ionospheric result.
#
# Usage:
#   ./diagnose_iono_LA_LB.sh
#   ./diagnose_iono_LA_LB.sh 2026172_2026184
#
# Outputs:
#   iono_correction/diagnostic/iono_diagnostic_report.txt
#   iono_correction/diagnostic/iono_diagnostic_3x3.png
#   iono_correction/diagnostic/iono_diagnostic_3x3.pdf
#

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="${NISAR_PROJECT_DIR:-$script_dir}"
project_dir="$(cd "$project_dir" && pwd)"
iono_dir="${IONO_OUTPUT_DIR:-$project_dir/iono_correction}"
diag_dir="${IONO_DIAGNOSTIC_DIR:-$iono_dir/diagnostic}"

if [[ $# -gt 1 ]]; then
    echo "Usage: $(basename "$0") [pair_name]" >&2
    exit 1
fi

if ! command -v gmt >/dev/null 2>&1; then
    echo "ERROR: GMT is not available in PATH." >&2
    exit 1
fi

pair_name="${1:-}"
if [[ -z "$pair_name" ]]; then
    mapfile -t common_pairs < <(
        comm -12 \
            <(find "$project_dir/LA/intf" -type f -name "unwrap.grd" \
                -printf '%h\n' | xargs -r -n1 basename | sort -u) \
            <(find "$project_dir/LB/intf" -type f -name "unwrap.grd" \
                -printf '%h\n' | xargs -r -n1 basename | sort -u)
    )
    if [[ ${#common_pairs[@]} -ne 1 ]]; then
        echo "ERROR: Expected exactly one common LA/LB pair." >&2
        printf 'Common pairs: %s\n' "${common_pairs[*]:-(none)}" >&2
        exit 1
    fi
    pair_name="${common_pairs[0]}"
fi

la_dir="$project_dir/LA/intf/$pair_name"
lb_dir="$project_dir/LB/intf/$pair_name"
la_grid="$la_dir/unwrap.grd"
lb_grid="$lb_dir/unwrap.grd"
a_on_b_grid="$iono_dir/unwrap_A_onB.grd"
raw_iono_grid="$iono_dir/iono_correction.grd"
filtered_iono_grid="$iono_dir/iono_correction_filt.grd"
corrected_grid="$iono_dir/unwrap_corrected.grd"

for grid in \
    "$la_grid" "$lb_grid" "$a_on_b_grid" "$raw_iono_grid" \
    "$filtered_iono_grid" "$corrected_grid"; do
    if [[ ! -f "$grid" ]]; then
        echo "ERROR: Required grid is missing: $grid" >&2
        exit 1
    fi
done

find_master_prm() {
    local linked_prm="$1"
    local search_dir="$2"
    local pattern="$3"
    local prm

    if [[ -e "$linked_prm" ]]; then
        printf '%s\n' "$linked_prm"
        return
    fi
    prm="$(find "$search_dir" -maxdepth 1 -type f -name "$pattern" \
        -print | sort | head -n 1)"
    if [[ -z "$prm" ]]; then
        return 1
    fi
    printf '%s\n' "$prm"
}

prm_a="$(find_master_prm "$iono_dir/master_A.PRM" "$la_dir" 'NSR_*A.PRM')" || {
    echo "ERROR: Cannot find the LA master PRM." >&2
    exit 1
}
prm_b="$(find_master_prm "$iono_dir/master_B.PRM" "$lb_dir" 'NSR_*B.PRM')" || {
    echo "ERROR: Cannot find the LB master PRM." >&2
    exit 1
}

lambda_a="$(awk '$1 == "radar_wavelength" {print $3; exit}' "$prm_a")"
lambda_b="$(awk '$1 == "radar_wavelength" {print $3; exit}' "$prm_b")"
if [[ -z "$lambda_a" || -z "$lambda_b" ]]; then
    echo "ERROR: radar_wavelength is missing from a master PRM." >&2
    exit 1
fi

read -r freq_a freq_b b_to_a gomba_factor < <(
    awk -v la="$lambda_a" -v lb="$lambda_b" 'BEGIN {
        c = 299792458.0
        fa = c / la
        fb = c / lb
        printf "%.15g %.15g %.15g %.15g\n",
            fa, fb, fa/fb, fb*fb/(fb*fb-fa*fa)
    }'
)

if ! awk -v fa="$freq_a" -v fb="$freq_b" \
    'BEGIN {exit !(fa > 0 && fb > fa)}'; then
    echo "ERROR: Expected f_B > f_A; obtained f_A=$freq_a, f_B=$freq_b." >&2
    exit 1
fi

mkdir -p "$diag_dir"

lb_scaled="$diag_dir/LB_scaled_to_fA.grd"
split_grid="$diag_dir/LA_minus_LB_scaled.grd"
split_trend="$diag_dir/split_trend_T.grd"
split_residual="$diag_dir/split_residual_D.grd"
original_subtraction="$diag_dir/input_minus_D_output.grd"
trend_identity_error="$diag_dir/input_minus_D_minus_T_abs.grd"
iono_from_split="$diag_dir/iono_recomputed_from_split.grd"
formula_error="$diag_dir/iono_formula_error.grd"

# Scale LB to the LA carrier frequency, then isolate the dispersive difference.
gmt grdmath "$lb_grid" "$b_to_a" MUL = "$lb_scaled"
gmt grdmath "$a_on_b_grid" "$lb_scaled" SUB = "$split_grid"

# Explicitly request both products, avoiding any ambiguity:
#   -T = fitted trend, -D = detrended residual.
gmt grdtrend "$split_grid" -N3 -T"$split_trend" -D"$split_residual"
gmt grdmath "$split_grid" "$split_residual" \
    SUB = "$original_subtraction"
gmt grdmath "$original_subtraction" "$split_trend" \
    SUB ABS = "$trend_identity_error"

# This is algebraically identical to the Gomba expression used by run7.
gmt grdmath "$split_grid" "$gomba_factor" MUL = "$iono_from_split"
gmt grdmath "$iono_from_split" "$raw_iono_grid" SUB ABS = "$formula_error"

grid_stat_line() {
    local label="$1"
    local grid="$2"
    gmt grdinfo "$grid" -C -L2 | awk -v label="$label" '
        {
            printf "%-27s %12.5g %12.5g %12.5g %12.5g %12.5g\n",
                label, $6, $7, $12, $13, $14
        }
    '
}

grid_mean_std() {
    gmt grdinfo "$1" -C -L2 | awk '{print $12, $13}'
}

grid_abs_max() {
    gmt grdinfo "$1" -C | awk '{m = ($6 < 0 ? -$6 : $6);
        n = ($7 < 0 ? -$7 : $7); print (m > n ? m : n)}'
}

read -r split_median split_l1 < <(
    gmt grdinfo "$split_grid" -C -L1 | awk '{print $12, $13}'
)
split_cycles="$(awk -v x="$split_median" \
    'BEGIN {printf "%.8g", x/(2*atan2(0,-1))}')"
predicted_bias="$(awk -v x="$split_median" -v g="$gomba_factor" \
    'BEGIN {printf "%.8g", x*g}')"
formula_max="$(gmt grdinfo "$formula_error" -C | awk '{print $7}')"
trend_identity_max="$(gmt grdinfo "$trend_identity_error" -C | awk '{print $7}')"

read -r la_mean la_std < <(grid_mean_std "$la_grid")
read -r corrected_mean corrected_std < <(grid_mean_std "$corrected_grid")
read -r raw_mean raw_std < <(grid_mean_std "$raw_iono_grid")
read -r filt_mean filt_std < <(grid_mean_std "$filtered_iono_grid")

std_ratio="$(awk -v a="$corrected_std" -v b="$la_std" \
    'BEGIN {if (b == 0) print "nan"; else printf "%.6g", a/b}')"

report="$diag_dir/iono_diagnostic_report.txt"
{
    echo "NISAR LA/LB ionospheric diagnostic"
    echo "=================================="
    echo "Project                    : $project_dir"
    echo "Pair                       : $pair_name"
    echo "LA master PRM              : $prm_a"
    echo "LB master PRM              : $prm_b"
    echo "f_A (Hz)                   : $freq_a"
    echo "f_B (Hz)                   : $freq_b"
    echo "LB-to-LA phase scale       : $b_to_a"
    echo "Gomba amplification factor : $gomba_factor"
    echo
    echo "Reference-offset test"
    echo "---------------------"
    echo "Median(A - B*f_A/f_B), rad : $split_median"
    echo "Median difference, cycles  : $split_cycles"
    echo "Predicted iono bias, rad    : $predicted_bias"
    echo "L1 scale of difference, rad: $split_l1"
    echo
    echo "Formula consistency test"
    echo "------------------------"
    echo "max|recomputed-current|, rad: $formula_max"
    echo
    echo "grdtrend output test"
    echo "--------------------"
    echo "Explicit -T file           : fitted trend"
    echo "Explicit -D file           : detrended residual"
    echo "Tested identity            : input - D_output = T_output"
    echo "max|input-D_output-T_output|: $trend_identity_max"
    echo "Meaning for original lines : input - trend_surface.grd returns"
    echo "                             the fitted trend when that file came from -D"
    echo
    echo "Grid statistics (radians)"
    echo "-------------------------"
    printf "%-27s %12s %12s %12s %12s %12s\n" \
        "grid" "minimum" "maximum" "mean" "std" "RMS"
    grid_stat_line "LA before" "$la_grid"
    grid_stat_line "LB scaled to f_A" "$lb_scaled"
    grid_stat_line "A-B scaled difference" "$split_grid"
    grid_stat_line "split fitted trend" "$split_trend"
    grid_stat_line "split residual" "$split_residual"
    grid_stat_line "raw ionosphere" "$raw_iono_grid"
    grid_stat_line "filtered ionosphere" "$filtered_iono_grid"
    grid_stat_line "LA after" "$corrected_grid"
    echo
    echo "Corrected/before std ratio : $std_ratio"
    echo
    echo "Quick interpretation"
    echo "--------------------"
    awk -v cyc="$split_cycles" -v bias="$predicted_bias" \
        -v ratio="$std_ratio" -v ferr="$formula_max" 'BEGIN {
        ac = (cyc < 0 ? -cyc : cyc)
        ab = (bias < 0 ? -bias : bias)
        if (ac >= 0.25)
            print "WARNING: LA/LB median reference mismatch is >= 0.25 cycle."
        else
            print "OK: LA/LB median reference mismatch is below 0.25 cycle."
        if (ab >= 3.141592653589793)
            print "WARNING: amplified median bias exceeds pi radians."
        else
            print "OK: amplified median bias is below pi radians."
        if (ratio + 0 > 1)
            print "WARNING: corrected LA has larger standard deviation than LA before."
        else
            print "OK: corrected LA standard deviation did not increase."
        if (ferr + 0 < 1e-2)
            print "OK: the saved raw ionosphere matches the split-spectrum formula."
        else
            print "WARNING: saved raw ionosphere does not match recomputation."
    }'
    echo "NOTE: standard deviation alone cannot distinguish deformation from noise."
} > "$report"

robust_symmetric_limit() {
    gmt grdinfo "$@" -C -L2 | awk '
        {
            lo = $12 - 2 * $13
            hi = $12 + 2 * $13
            if (lo < 0) lo = -lo
            if (hi < 0) hi = -hi
            if (lo > lim) lim = lo
            if (hi > lim) lim = hi
        }
        END {
            if (!(lim > 0)) lim = 1
            printf "%.12g\n", lim
        }
    '
}

make_symmetric_cpt() {
    local limit="$1"
    local cpt="$2"
    local lower upper increment
    lower="$(awk -v x="$limit" 'BEGIN {printf "%.12g", -x}')"
    upper="$(awk -v x="$limit" 'BEGIN {printf "%.12g", x}')"
    increment="$(awk -v x="$limit" 'BEGIN {printf "%.12g", 2*x/100}')"
    gmt makecpt -Cvik -T"${lower}/${upper}/${increment}" -Z > "$cpt"
}

phase_limit="$(robust_symmetric_limit \
    "$a_on_b_grid" "$lb_scaled" "$la_grid" "$corrected_grid")"
diff_limit="$(robust_symmetric_limit \
    "$split_grid" "$split_trend" "$split_residual")"
iono_limit="$(robust_symmetric_limit \
    "$raw_iono_grid" "$filtered_iono_grid")"

phase_cpt="$diag_dir/phase.cpt"
diff_cpt="$diag_dir/difference.cpt"
iono_cpt="$diag_dir/ionosphere.cpt"
make_symmetric_cpt "$phase_limit" "$phase_cpt"
make_symmetric_cpt "$diff_limit" "$diff_cpt"
make_symmetric_cpt "$iono_limit" "$iono_cpt"

output_base="$diag_dir/iono_diagnostic_3x3"

gmt begin "$output_base" png,pdf
    gmt set \
        FONT_TITLE 12p \
        FONT_LABEL 8p \
        FONT_ANNOT_PRIMARY 7p \
        MAP_TITLE_OFFSET 4p \
        MAP_FRAME_TYPE plain \
        COLOR_NAN 150/150/150

    gmt subplot begin 3x3 \
        -Fs9.2c/5.8c \
        -M0.25c/0.9c \
        -T"NISAR LA/LB ionospheric diagnostic: $pair_name"

        gmt subplot set 0,0
        gmt grdimage "$a_on_b_grid" -C"$phase_cpt" -JX? \
            -Baf -BWSen+t"(a) LA resampled on LB"
        gmt colorbar -C"$phase_cpt" -DJBC+w6c/0.2c+h+o0/0.42c \
            -Baf+l"Phase (rad)"

        gmt subplot set 0,1
        gmt grdimage "$lb_scaled" -C"$phase_cpt" -JX? \
            -Baf -BWSen+t"(b) LB scaled to f_A"
        gmt colorbar -C"$phase_cpt" -DJBC+w6c/0.2c+h+o0/0.42c \
            -Baf+l"Phase (rad)"

        gmt subplot set 0,2
        gmt grdimage "$split_grid" -C"$diff_cpt" -JX? \
            -Baf -BWSen+t"(c) LA - scaled LB"
        gmt colorbar -C"$diff_cpt" -DJBC+w6c/0.2c+h+o0/0.42c \
            -Baf+l"Difference (rad)"

        gmt subplot set 1,0
        gmt grdimage "$split_trend" -C"$diff_cpt" -JX? \
            -Baf -BWSen+t"(d) Explicit -T fitted trend"
        gmt colorbar -C"$diff_cpt" -DJBC+w6c/0.2c+h+o0/0.42c \
            -Baf+l"Difference (rad)"

        gmt subplot set 1,1
        gmt grdimage "$split_residual" -C"$diff_cpt" -JX? \
            -Baf -BWSen+t"(e) Explicit -D residual"
        gmt colorbar -C"$diff_cpt" -DJBC+w6c/0.2c+h+o0/0.42c \
            -Baf+l"Difference (rad)"

        gmt subplot set 1,2
        gmt grdimage "$raw_iono_grid" -C"$iono_cpt" -JX? \
            -Baf -BWSen+t"(f) Raw ionosphere"
        gmt colorbar -C"$iono_cpt" -DJBC+w6c/0.2c+h+o0/0.42c \
            -Baf+l"Ionospheric phase (rad)"

        gmt subplot set 2,0
        gmt grdimage "$filtered_iono_grid" -C"$iono_cpt" -JX? \
            -Baf -BWSen+t"(g) Filtered ionosphere on LA"
        gmt colorbar -C"$iono_cpt" -DJBC+w6c/0.2c+h+o0/0.42c \
            -Baf+l"Ionospheric phase (rad)"

        gmt subplot set 2,1
        gmt grdimage "$la_grid" -C"$phase_cpt" -JX? \
            -Baf -BWSen+t"(h) LA before correction"
        gmt colorbar -C"$phase_cpt" -DJBC+w6c/0.2c+h+o0/0.42c \
            -Baf+l"Phase (rad)"

        gmt subplot set 2,2
        gmt grdimage "$corrected_grid" -C"$phase_cpt" -JX? \
            -Baf -BWSen+t"(i) LA after correction"
        gmt colorbar -C"$phase_cpt" -DJBC+w6c/0.2c+h+o0/0.42c \
            -Baf+l"Phase (rad)"

    gmt subplot end
gmt end

echo "Diagnostic completed."
echo "Report : $report"
echo "Figure : ${output_base}.png"
echo "PDF    : ${output_base}.pdf"
echo
sed -n '/Reference-offset test/,$p' "$report"
