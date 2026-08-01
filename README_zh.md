# 基于GMTSAR的NISAR DInSAR LA/LB处理流程

本仓库整理了一套基于GMTSAR的两景NISAR DInSAR研究流程，包括LA/LB双频通道准备、干涉处理、陆地掩膜、SNAPHU解缠、分裂频谱电离层估计，以及校正后LA相位的再次解缠和LOS产品生成。

> 这是一套研究脚本，不是NASA/JPL或GMTSAR官方处理器。每个区域都必须独立检查相干性、解缠连通区、相位参考以及电离层校正结果。

## run1–run8

1. `run1_get_nisar_make_dem_kml.py`：读取NISAR覆盖范围KML并准备DEM。
2. `run2_prepare_NISAR_LA_LB.sh`：建立LA/LB目录及GMTSAR配置。
3. `run3_process_NISAR_LA_LB.sh`：分别进行LA/LB干涉处理。
4. `run4_make_landmask_ra.sh`：制作雷达坐标陆地掩膜。
5. `run5_presnaphu_preview.sh`：在解缠前检查缠绕相位和相干性。
6. `run6_unwrap_interp_geocode_LA_LB.sh`：相位插值、SNAPHU解缠和地理编码。
7. `run7_nsr_iono_LA_LB.sh`：利用LA/LB分裂频谱估计并滤波电离层相位。
8. `run8_iono_corrected_LA.sh`：对校正后的LA相位重新解缠，生成LOS和地理坐标产品。

## 基本运行方式

```bash
python3 run1_get_nisar_make_dem_kml.py
./run2_prepare_NISAR_LA_LB.sh
./run3_process_NISAR_LA_LB.sh
./run4_make_landmask_ra.sh
./run5_presnaphu_preview.sh 0.1
./run6_unwrap_interp_geocode_LA_LB.sh 0.1 0
./run7_nsr_iono_LA_LB.sh
./run8_iono_corrected_LA.sh 0.1 0
```

必须逐步检查，不能发现run6解缠台阶后仍直接进入run7。LA/LB之间的整数周或相位参考误差会被Gomba系数明显放大。

## 关键参数

run6的插值半径单位是网格像元，默认300：

```bash
NEAREST_GRID_RADIUS=1000 \
./run6_unwrap_interp_geocode_LA_LB.sh 0.1 0
```

增大半径可以跨过较宽的低相干空洞，但也可能错误连接彼此独立的区域。修改后必须检查`conncomp.grd`和`unwrap.grd`。

run7的电离层滤波波长单位是米，默认20 km：

```bash
IONO_FILTER_WAVELENGTH=10000 \
IONO_OUTPUT_DIR="$PWD/iono_correction_10km" \
./run7_nsr_iono_LA_LB.sh
```

测试不同尺度时应使用独立输出目录，避免覆盖已有结果。

## 示例结果

### T126D轨道

![T126D电离层校正缠绕相位](docs/images/t126d-ionospheric-correction-wrapped-phase.png)

### T54D轨道

![T54D电离层校正缠绕相位](docs/images/t54d-ionospheric-correction-wrapped-phase.png)

## 维护者相关论文

Wang, X., Li, D., Zhu, J., Xu, X., Li, Z., Sandwell, D. T., Hao, D., Liu, C.,
and Fang, R. (2026). Near instantaneously triggered Mw 5.9 aftershock during
the 2025 Mw 7.1 Dingri earthquake revealed by radar interferometry. *Earth and
Planetary Science Letters*, **686**, 120070.
[https://doi.org/10.1016/j.epsl.2026.120070](https://doi.org/10.1016/j.epsl.2026.120070)

## 数据与授权

仓库不包含NISAR HDF5、DEM、SLC、GRD、干涉图、日志、PDF、PNG、KML或其他计算结果。数据使用应遵守相应的数据分发条款。

电离层估计采用Gomba等（2016）的分裂频谱方法；后续脚本由Yajun Zhang发展；NISAR LA/LB流程最终由Xin Wang（中国科学技术大学，合肥）更新完成。

## 许可证

本仓库采用GNU General Public License v3.0，详见[LICENSE](LICENSE)。第三方软件和数据仍适用其各自的许可证与分发条款。
