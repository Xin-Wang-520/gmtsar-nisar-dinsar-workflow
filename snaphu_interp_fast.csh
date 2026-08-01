#!/bin/csh -f
#
# Fast version of GMTSAR snaphu_interp.csh.
#
# nearest_grid is replaced by nearest_grid_c_exact.py, which reproduces
# the original C program's z values, NaN extent, equidistant-candidate
# ordering, and radius-boundary behavior while using a faster distance
# transform.
#
# Modified by : Xin Wang
# Affiliation : University of Science and Technology of China (USTC)
#               Hefei, China
# Updated     : 2026-07-29
#

alias rm 'rm -f'
unset noclobber

if ($#argv < 2) then
  echo ""
  echo "Usage: snaphu_interp_fast.csh correlation_threshold maximum_discontinuity [rng0/rngf/azi0/azif]"
  echo ""
  echo "This version uses nearest_grid_c_exact.py."
  echo "Set NEAREST_GRID_PYTHON when python3 does not contain scipy and netCDF4."
  echo "Example: setenv NEAREST_GRID_PYTHON /path/to/conda/env/bin/python3"
  echo ""
  exit 1
endif

if (-f ~/.quiet) then
  set V = ""
else
  set V = "-V"
endif

# Locate nearest_grid_c_exact.py beside this script.  Calling this script with an
# absolute path or ./snaphu_interp_fast.csh is recommended on a server.
set script_file = "$0"
if ("$script_file" !~ */*) then
  set located = `which "$script_file"`
  if ($status == 0) set script_file = "$located"
endif
set script_dir = "$script_file:h"
set exact_interp = "$script_dir/nearest_grid_c_exact.py"
if (! -f "$exact_interp") then
  echo "ERROR: cannot find $exact_interp"
  exit 1
endif

set python_cmd = "python3"
if ($?NEAREST_GRID_PYTHON) then
  set python_cmd = "$NEAREST_GRID_PYTHON"
endif

# Maximum nearest-neighbour search radius in grid cells.  Keep the historical
# GMTSAR value of 300 by default, but allow large low-coherence gaps to be
# tested without editing this script.  A value of 0 fills every NaN that has
# at least one valid sample somewhere in the grid.
set interp_radius = 300
if ($?NEAREST_GRID_RADIUS) then
  set interp_radius = "$NEAREST_GRID_RADIUS"
endif
if ($interp_radius < 0) then
  echo "ERROR: NEAREST_GRID_RADIUS must be zero or a positive integer"
  exit 1
endif

# Prepare the phase, correlation, and masks.
if ($#argv == 3) then
  gmt grdcut mask.grd -R$3 -Gmask_patch.grd
  gmt grdcut corr.grd -R$3 -Gcorr_patch.grd
  gmt grdcut phasefilt.grd -R$3 -Gphase_patch.grd
else
  ln -s mask.grd mask_patch.grd
  ln -s corr.grd corr_patch.grd
  ln -s phasefilt.grd phase_patch.grd
endif

if (-f landmask_ra.grd) then
  if ($#argv == 3) then
    gmt grdsample landmask_ra.grd -R$3 `gmt grdinfo -I phase_patch.grd` -Glandmask_ra_patch.grd
  else
    gmt grdsample landmask_ra.grd `gmt grdinfo -I phase_patch.grd` -Glandmask_ra_patch.grd
  endif
  gmt grdmath phase_patch.grd landmask_ra_patch.grd MUL = phase_patch.grd $V
endif

if (-f mask_def.grd) then
  if ($#argv == 3) then
    gmt grdcut mask_def.grd -R$3 -Gmask_def_patch.grd
  else
    cp mask_def.grd mask_def_patch.grd
  endif
  gmt grdmath corr_patch.grd mask_def_patch.grd MUL = corr_patch.grd $V
endif

gmt grdmath corr_patch.grd $1 GE 0 NAN mask_patch.grd MUL = mask2_patch.grd
gmt grdmath corr_patch.grd 0. XOR 1. MIN = corr_patch.grd
gmt grdmath mask2_patch.grd corr_patch.grd MUL = corr_tmp.grd
gmt grdmath mask2_patch.grd phase_patch.grd MUL = phase_tmp.grd

echo "C-exact fast Python nearest-neighbour interpolation ..."
echo "Nearest-grid search radius: $interp_radius cells"
rm tmp.grd
$python_cmd "$exact_interp" phase_tmp.grd tmp.grd $interp_radius
if ($status != 0) then
  echo "ERROR: nearest_grid_c_exact.py failed"
  exit 1
endif
mv tmp.grd phase_tmp.grd

gmt grd2xyz phase_tmp.grd -ZTLf -do0 > phase.in
gmt grd2xyz corr_tmp.grd -ZTLf -do0 > corr.in

# Run the original SNAPHU calculation.
set sharedir = `gmtsar_sharedir.csh`
echo "unwrapping phase with snaphu - higher threshold for faster unwrapping"
if ($2 == 0) then
  snaphu phase.in `gmt grdinfo -C phase_patch.grd | cut -f 10` -f $sharedir/snaphu/config/snaphu.conf.brief -c corr.in -o unwrap.out -v -s -g conncomp.out
else
  sed "s/.*DEFOMAX_CYCLE.*/DEFOMAX_CYCLE  $2/g" $sharedir/snaphu/config/snaphu.conf.brief > snaphu.conf.brief
  snaphu phase.in `gmt grdinfo -C phase_patch.grd | cut -f 10` -f snaphu.conf.brief -c corr.in -o unwrap.out -v -d -g conncomp.out
endif

# Convert SNAPHU output back to GMT grids.
gmt xyz2grd unwrap.out -ZTLf -r `gmt grdinfo -I- phase_patch.grd` `gmt grdinfo -I phase_patch.grd` -Gtmp.grd
gmt xyz2grd conncomp.out -ZTLu -r `gmt grdinfo -I- phase_patch.grd` `gmt grdinfo -I phase_patch.grd` -Gconncomp.grd
gmt grdmath tmp.grd mask2_patch.grd MUL = tmp.grd
mv tmp.grd unwrap.grd

if (-f landmask_ra.grd) then
  gmt grdmath unwrap.grd landmask_ra_patch.grd MUL = tmp.grd $V
  mv tmp.grd unwrap.grd
endif

if (-f mask_def.grd) then
  gmt grdmath unwrap.grd mask_def_patch.grd MUL = tmp.grd $V
  mv tmp.grd unwrap.grd
endif

# Plot the unwrapped result, matching snaphu_interp.csh.
gmt grdgradient unwrap.grd -Nt.9 -A0. -Gunwrap_grad.grd
set tmp = `gmt grdinfo -C -L2 unwrap.grd`
set limitU = `echo $tmp | awk '{printf("%5.1f", $12+$13*2)}'`
set limitL = `echo $tmp | awk '{printf("%5.1f", $12-$13*2)}'`
gmt makecpt -Cseis -I -Z -T"$limitL"/"$limitU"/1 -D > unwrap.cpt
gmt grdimage unwrap.grd -Iunwrap_grad.grd -Cunwrap.cpt -JX6.5i -Bxaf+lRange -Byaf+lAzimuth -BWSen -X1.3i -Y3i -P -K > unwrap.ps
gmt psscale -Runwrap.grd -J -DJTC+w5/0.2+h+e -Cunwrap.cpt -Bxaf+l"Unwrapped phase" -By+lrad -O >> unwrap.ps
gmt psconvert -Tf -P -A -Z unwrap.ps
echo "Unwrapped phase map: unwrap.pdf"

# Clean temporary products, retaining the same main outputs as the original.
rm tmp.grd corr_tmp.grd unwrap.out tmp2.grd unwrap_grad.grd conncomp.out
rm phase.in corr.in
mv -f phase_patch.grd phasefilt_interp.grd
if ($#argv == 3) mv corr_patch.grd corr_cut.grd
rm mask_patch.grd mask3.grd mask3.out
rm corr_patch.grd corr_cut.grd
