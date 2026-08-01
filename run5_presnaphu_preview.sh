#!/usr/bin/env bash
# Modified by Xin Wang, USTC, Hefei, China
# Run 5: Pre-SNAPHU preview with mandatory landmask
#
# NISAR LA/LB independent interferogram processing

set -euo pipefail

export LC_ALL=C
export LANG=C
export LANGUAGE=C


DEFAULT_CORR_THRESHOLD="0.1"


die(){
    echo "[ERROR] $*" >&2
    exit 1
}


CORR_THRESHOLD="${1:-${DEFAULT_CORR_THRESHOLD}}"


[[ "${CORR_THRESHOLD}" =~ ^[0-9.]+$ ]] ||
    die "Invalid correlation threshold"


command -v gmt >/dev/null ||
    die "GMT not found"


ROOT_DIR="$(pwd -P)"


[[ -d LA ]] || die "Missing LA/"
[[ -d LB ]] || die "Missing LB/"


TMP_ROOT=$(mktemp -d /tmp/run5_presnaphu.XXXXXX)


cleanup(){
    rm -rf "${TMP_ROOT}"
}

trap cleanup EXIT



process_intf(){

    local CHANNEL="$1"
    local INTD="$2"


    cd "${INTD}"


    echo
    echo "========================================"
    echo "[${CHANNEL}] Processing"
    echo "$(pwd)"
    echo "========================================"


    for f in phasefilt.grd corr.grd mask.grd landmask_ra.grd
    do
        [[ -s "${f}" ]] ||
            die "${CHANNEL}: missing ${f}"
    done


    OUTDIR="presnaphu_pdf"

    rm -rf "${OUTDIR}"
    mkdir -p "${OUTDIR}"


    WORK="${TMP_ROOT}/${CHANNEL}_$(basename "${INTD}")"

    mkdir -p "${WORK}"


    MASK="${WORK}/mask_presnaphu.grd"
    PHASE="${WORK}/phase_presnaphu.grd"



    echo "[${CHANNEL}] Correlation threshold : ${CORR_THRESHOLD}"

    echo "[${CHANNEL}] Apply corr mask"

    gmt grdmath \
        corr.grd ${CORR_THRESHOLD} GE 0 NAN \
        mask.grd 0 GT 0 NAN MUL \
        = "${WORK}/mask1.grd"



    echo "[${CHANNEL}] Apply land mask"


    gmt grdmath \
        "${WORK}/mask1.grd" \
        landmask_ra.grd 0 GT 0 NAN MUL \
        = "${MASK}"



    echo "[${CHANNEL}] Apply mask to phase"


    gmt grdmath \
        phasefilt.grd \
        "${MASK}" MUL \
        = "${PHASE}"



    echo "[${CHANNEL}] Plot mask"


    gmt makecpt \
        -Cgray \
        -T0/1/0.05 \
        -Z \
        > "${WORK}/mask.cpt"


    gmt begin "${OUTDIR}/mask_presnaphu" pdf


        gmt set \
            MAP_FRAME_TYPE plain \
            FONT_ANNOT_PRIMARY 10p \
            FONT_LABEL 11p \
            COLOR_NAN white


        gmt grdimage \
            "${MASK}" \
            -JX7i \
            -C"${WORK}/mask.cpt" \
            -Bxaf+l"Range" \
            -Byaf+l"Azimuth" \
            -BWSen+t"Pre-SNAPHU mask (corr >= ${CORR_THRESHOLD})"


    gmt end



    echo "[${CHANNEL}] Plot phase"


    gmt makecpt \
        -Ccyclic \
        -T-3.141592653/3.141592653/0.02 \
        -Z \
        > "${WORK}/phase.cpt"



    gmt begin "${OUTDIR}/phase_presnaphu" pdf


        gmt set \
            MAP_FRAME_TYPE plain \
            FONT_ANNOT_PRIMARY 10p \
            FONT_LABEL 11p \
            COLOR_NAN white


        gmt grdimage \
            "${PHASE}" \
            -JX7i \
            -C"${WORK}/phase.cpt" \
            -Bxaf+l"Range" \
            -Byaf+l"Azimuth" \
            -BWSen+t"Pre-SNAPHU phase (corr >= ${CORR_THRESHOLD})"


        gmt colorbar \
            -DJBC+w5i/0.25i+h \
            -C"${WORK}/phase.cpt" \
            -Bxa1.57f0.785+l"Phase(rad)"


    gmt end



    [[ -s "${OUTDIR}/mask_presnaphu.pdf" ]] ||
        die "${CHANNEL}: mask pdf failed"


    [[ -s "${OUTDIR}/phase_presnaphu.pdf" ]] ||
        die "${CHANNEL}: phase pdf failed"



    echo "[${CHANNEL}] Done"

}



run_channel(){

    local CHANNEL="$1"


    find "${CHANNEL}/intf" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -name "20*" \
        | sort \
        | while read -r INTD
    do
        process_intf "${CHANNEL}" "${ROOT_DIR}/${INTD}"
    done

}



echo "========================================"
echo "Run 5 Pre-SNAPHU preview"
echo "Root      : ${ROOT_DIR}"
echo "Threshold : ${CORR_THRESHOLD}"
echo "Landmask  : REQUIRED"
echo "========================================"



run_channel LA &
PID_LA=$!


run_channel LB &
PID_LB=$!


echo "LA PID: ${PID_LA}"
echo "LB PID: ${PID_LB}"


wait ${PID_LA}
STATUS_LA=$?


wait ${PID_LB}
STATUS_LB=$?



if [[ ${STATUS_LA} != 0 || ${STATUS_LB} != 0 ]]
then
    die "Run 5 failed"
fi



echo
echo "========================================"
echo "[DONE] Run 5 completed"
echo
echo "Outputs:"
echo " LA/intf/*/presnaphu_pdf/"
echo " LB/intf/*/presnaphu_pdf/"
echo
echo "Only PDF files are kept."
echo "========================================"
