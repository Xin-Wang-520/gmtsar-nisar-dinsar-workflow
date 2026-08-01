#!/usr/bin/env bash
# Modified by Xin Wang, USTC, Hefei, China
#
# Run 4: generate NISAR LA/LB radar-coordinate land mask
#
# Run:
#   ./run4_make_landmask_ra.sh
#   ./run4_make_landmask_ra.sh 1
#
# Output:
#   LA/intf/*/landmask_ra.grd
#   LA/intf/*/landmask_ra.pdf
#   LB/intf/*/landmask_ra.grd
#   LB/intf/*/landmask_ra.pdf

set -euo pipefail

export LC_ALL=C
export LANG=C
export LANGUAGE=C


die()
{
    echo "[ERROR] $*" >&2
    exit 1
}


grid_signature()
{
    gmt grdinfo "$1" -C | awk '{
        print $2,$3,$4,$5,$8,$9,$10,$11,$12
    }'
}


find_intf()
{
    local channel=$1

    find "${channel}/intf" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        | sort \
        | head -1
}


check_env()
{
    echo "========================================"
    echo "Run 4 environment check"

    echo "Conda environment : ${CONDA_DEFAULT_ENV:-none}"
    echo "Conda prefix      : ${CONDA_PREFIX:-none}"

    command -v gmt >/dev/null ||
        die "GMT not found"

    command -v landmask.csh >/dev/null ||
        die "landmask.csh not found"

    command -v proj_ll2ra.csh >/dev/null ||
        die "proj_ll2ra.csh not found"


    echo "GMT               : $(which gmt)"
    echo "GMT version       : $(gmt --version)"
    echo "landmask.csh      : $(which landmask.csh)"
    echo "proj_ll2ra.csh    : $(which proj_ll2ra.csh)"

    echo "========================================"
}


check_input()
{
    local ch=$1

    local intf
    intf=$(find_intf "${ch}")

    [[ -d "${intf}" ]] ||
        die "${ch}: no intf directory"


    [[ -s "${intf}/phasefilt.grd" ]] ||
        die "${ch}: missing phasefilt.grd"


    [[ -s "${intf}/trans.dat" ]] ||
        die "${ch}: missing trans.dat"


    [[ -s "${ch}/topo/dem.grd" ]] ||
        die "${ch}: missing topo/dem.grd"


    local size
    size=$(wc -c < "${intf}/trans.dat")


    (( size > 20*1024*1024 )) ||
        die "${ch}: trans.dat too small"


    echo "----------------------------------------"
    echo "Channel                 : ${ch}"
    echo "DEM                     : ${ch}/topo/dem.grd"
    echo "Interferogram directory : ${intf}"
    echo "trans.dat               : $(awk \
        -v s=${size} \
        'BEGIN{printf "%.2f MiB",s/1024/1024}')"

    echo "Template                : ${intf}/phasefilt.grd"
    echo "Template signature      : $(grid_signature ${intf}/phasefilt.grd)"

    echo "----------------------------------------"
}


make_landmask()
{
    local ch=$1


    local intf
    intf=$(find_intf "${ch}")


    cd "${intf}"


    echo "[${ch}] ========================================"
    echo "[${ch}] Start landmask"
    echo "[${ch}] Directory: $(pwd)"
    echo "[${ch}] ========================================"


    echo "[${ch}] STEP 1: link DEM"


    rm -f dem.grd


    ln -s ../../topo/dem.grd dem.grd


    [[ -e dem.grd ]] ||
        die "${ch}: DEM link failed"


    echo "[${ch}] DEM:"
    ls -l dem.grd



    echo "[${ch}] STEP 2: remove old products"


    rm -f \
        landmask.grd \
        landmask_ra.grd \
        landmask_ra.pdf \
        landmask_ra.xyz \
        tmp.grd \
        landmask_ra.cpt \
        landmask_ra.ps \
        gmt.conf \
        gmt.history



    local region

    region=$(gmt grdinfo phasefilt.grd -C |
        awk '{print $2"/"$3"/"$4"/"$5}')


    echo "[${ch}] Region: ${region}"



    echo "[${ch}] STEP 3: run landmask.csh"


    landmask.csh "${region}"


    [[ -s landmask_ra.grd ]] ||
        die "${ch}: landmask_ra.grd not generated"



    echo "[${ch}] STEP 4: match phasefilt grid"


    gmt grdsample \
        landmask_ra.grd \
        -Rphasefilt.grd \
        -Gtmp.grd


    mv tmp.grd landmask_ra.grd



    echo "[${ch}] STEP 5: check grid"


    echo "phasefilt:"
    gmt grdinfo phasefilt.grd -C


    echo "landmask:"
    gmt grdinfo landmask_ra.grd -C



    [[ "$(grid_signature phasefilt.grd)" == \
       "$(grid_signature landmask_ra.grd)" ]] ||
       die "${ch}: landmask grid mismatch"



    echo "[${ch}] STEP 6: plot PDF"



    cat > landmask_ra.cpt << EOF
0 160 160 160 0.5 160 160 160
0.5 255 0 0 1 255 0 0
B 160 160 160
F 255 0 0
N 160 160 160
EOF



    gmt grdimage landmask_ra.grd \
        -JX6.5i \
        -Clandmask_ra.cpt \
        -Bxaf+lRange \
        -Byaf+lAzimuth \
        -BWSen+t"${ch} Radar Land Mask" \
        -P \
        -K > landmask_ra.ps



    gmt psscale \
        -Rlandmask_ra.grd \
        -J \
        -DJBC+w5i/0.25i+h+o0/0.35i \
        -Clandmask_ra.cpt \
        -Bxa0.5+l"Land mask" \
        -O >> landmask_ra.ps



    gmt psconvert \
        landmask_ra.ps \
        -Tf \
        -A \
        -Z



    [[ -s landmask_ra.pdf ]] ||
        die "${ch}: PDF generation failed"



    rm -f \
        landmask_ra.cpt \
        landmask_ra.ps \
        landmask_ra.xyz \
        gmt.conf \
        gmt.history


    echo "[${ch}] DONE"
    echo "[${ch}] Output:"
    echo "  $(pwd)/landmask_ra.grd"
    echo "  $(pwd)/landmask_ra.pdf"

}



main()
{

    check_env


    check_input LA
    check_input LB



    if [[ "${1:-}" != "1" ]]; then

        echo
        echo "[CHECK ONLY]"
        echo "Run:"
        echo "  ./run4_make_landmask_ra.sh 1"

        exit 0
    fi



    echo "========================================"
    echo "Run 4: LA and LB parallel"
    echo "========================================"



    make_landmask LA &
    pid_LA=$!


    make_landmask LB &
    pid_LB=$!


    echo "LA PID : ${pid_LA}"
    echo "LB PID : ${pid_LB}"


    fail=0


    wait ${pid_LA} || fail=1
    wait ${pid_LB} || fail=1


    [[ ${fail} == 0 ]] ||
        die "LA or LB failed"


    echo "========================================"
    echo "Run 4 finished successfully"
    echo "========================================"

}


main "$@"
