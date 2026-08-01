#!/usr/bin/env bash
# Modified by Xin Wang, USTC, Hefei, China
# Prepare NISAR RSLC LA/LB directories for GMTSAR NSR processing
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


ROOT=$(pwd -P)

RAW="${ROOT}/raw"
TOPO="${ROOT}/topo"


[[ -d "${RAW}" ]] || die "raw directory missing"
[[ -d "${TOPO}" ]] || die "topo directory missing"

[[ -s "${TOPO}/dem.grd" ]] ||
    die "topo/dem.grd missing"



echo "========================================"
echo "Run 2: Prepare NISAR LA/LB"
echo "ROOT: ${ROOT}"
echo "========================================"



# --------------------------------
# Find NISAR RSLC files
# --------------------------------

mapfile -t H5_FILES < <(
    find "${RAW}" -maxdepth 1 \
    -name "NISAR_L1_PR_RSLC_*_J_001.h5" \
    | sort
)


if [[ ${#H5_FILES[@]} -ne 2 ]]; then
    die "Need exactly two RSLC h5 files, found ${#H5_FILES[@]}"
fi


MASTER=$(basename "${H5_FILES[0]}" .h5)
SLAVE=$(basename "${H5_FILES[1]}" .h5)


echo "[MASTER]"
echo "${MASTER}"

echo "[SLAVE]"
echo "${SLAVE}"



# --------------------------------
# Create LA/LB
# --------------------------------

mkdir -p LA/raw LA/topo
mkdir -p LB/raw LB/topo



# --------------------------------
# Link RSLC and DEM
# --------------------------------

for CH in LA LB
do

    echo "[LINK] ${CH}"

    ln -sfn ../../raw/${MASTER}.h5 \
        ${CH}/raw/${MASTER}.h5

    ln -sfn ../../raw/${SLAVE}.h5 \
        ${CH}/raw/${SLAVE}.h5


    ln -sfn ../../topo/dem.grd \
        ${CH}/topo/dem.grd

done



# --------------------------------
# Generate config
# --------------------------------

command -v pop_config.csh >/dev/null 2>&1 ||
    die "pop_config.csh not found"


echo "[CONFIG] LA"

(
cd LA
pop_config.csh NSR_A > config_NSR_A.txt
)


echo "[CONFIG] LB"

(
cd LB
pop_config.csh NSR_B > config_NSR_B.txt
)



echo "========================================"
echo "[DONE] NISAR LA/LB preparation finished"
echo
echo "LA:"
echo "  config_NSR_A.txt"
echo "  raw/*.h5"
echo "  topo/dem.grd"
echo
echo "LB:"
echo "  config_NSR_B.txt"
echo "  raw/*.h5"
echo "  topo/dem.grd"
echo "========================================"

