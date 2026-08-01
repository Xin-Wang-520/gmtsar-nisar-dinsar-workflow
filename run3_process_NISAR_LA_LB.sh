#!/usr/bin/env bash
# Modified by Xin Wang, USTC, Hefei, China
# Run GMTSAR NISAR NSR processing for LA/LB
# Date: July 25, 2026

set -euo pipefail

export LC_ALL=C
export LANG=C
export LANGUAGE=C


die()
{
    echo "[ERROR] $*" >&2
    exit 1
}


command -v p2p_processing_nsr.csh >/dev/null 2>&1 ||
    die "p2p_processing_nsr.csh not found"


ROOT=$(pwd -P)


[[ -d LA ]] || die "LA directory missing"
[[ -d LB ]] || die "LB directory missing"



get_rslc()
{
    local dir=$1

    find "${dir}/raw" \
        -maxdepth 1 \
        -name "NISAR_L1_PR_RSLC_*_J_001.h5" \
        | sed 's/.h5$//' \
        | sort
}



mapfile -t LA_FILES < <(get_rslc LA)

if [[ ${#LA_FILES[@]} -ne 2 ]]; then
    die "LA needs exactly two RSLC files, found ${#LA_FILES[@]}"
fi


MASTER=$(basename "${LA_FILES[0]}")
SLAVE=$(basename "${LA_FILES[1]}")


echo "========================================"
echo "Run 3: NISAR LA/LB P2P processing"
echo
echo "MASTER:"
echo "${MASTER}"
echo
echo "SLAVE:"
echo "${SLAVE}"
echo "========================================"



run_nsr()
{
    local channel=$1
    local sat=$2
    local config=$3

    echo "[START] ${channel}"

    cd "${ROOT}/${channel}"

    rm -f p2p_${channel}.log

    nohup p2p_processing_nsr.csh \
        "${sat}" \
        "${MASTER}" \
        "${SLAVE}" \
        "${config}" \
        > p2p_${channel}.log 2>&1 &

    echo $! > p2p_${channel}.pid

    echo "[PID] ${channel}: $(cat p2p_${channel}.pid)"
}



run_nsr LA NSR_A config_NSR_A.txt
run_nsr LB NSR_B config_NSR_B.txt



echo "========================================"
echo "Processing started"
echo
echo "Monitor:"
echo "  tail -f LA/p2p_LA.log"
echo "  tail -f LB/p2p_LB.log"
echo
echo "PID:"
echo "  cat LA/p2p_LA.pid"
echo "  cat LB/p2p_LB.pid"
echo "========================================"

