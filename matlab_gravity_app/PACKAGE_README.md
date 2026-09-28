# 全球重力场与地表环境 · 离线运行包

**完整解压后，在 MATLAB 中打开 `START_HERE.m`，点击“运行”即可。** 启动脚本会自动找到程序与数据，无需手动添加路径、联网下载、安装 Python 或额外工具箱。请先解压整个文件夹，不要直接从压缩包内运行文件。

## 运行环境

- MATLAB **R2022b 或更新版本**，使用普通桌面模式及 MATLAB 自带的 Java 环境（JVM）。
- 需要完整 MATLAB；单独安装 MATLAB Runtime 不能运行此源代码包。
- 保持包内目录结构完整。运行数据均已附带，日常使用可以离线进行。

## 包含的功能

可旋转的三维地球、Miller 等四种平面投影，展示总重力、重力扰动、地表 / 海底高程和离心量；包含国界、197 国首都与中英文搜索、个人重力与离心力计算、三档显示质量，以及二维离心图随当前区域调整的局部色标。

## 包内材料

| 文件 / 目录 | 内容 |
|---|---|
| `START_HERE.m` | 启动入口 |
| 根目录其余 `.m` 文件 | 应用与计算函数 |
| `data/gravity_grid.mat` | EGM2008 总重力与重力扰动网格 |
| `data/gravity_egm2008_n180_coefficients.mat` | EGM2008 180 阶模型系数 |
| `data/world_geodata.mat` | 国界、首都与国家目录 |
| `data/terrain_data.mat` | 地表 / 海底高程、大地水准面与首都环境数据 |
| `data/centrifugal_cache.mat` | 已计算的地表离心量缓存 |
| `SOURCES.md`、`data/` 内来源与许可说明 | 数据出处、使用口径及许可 |
| `docs/` | Markdown 功能宣传册、配图与宣传册长图 |
| `tests/` | 可选的 MATLAB 验证测试 |

缓存与随包数据相匹配时直接复用；数据或算法变化后会自动重建。若应用目录不可写，程序会尝试将新缓存保存到 MATLAB 的用户配置目录。

## 数据说明与验证

重力采用 EGM2008 观测资料融合模型；本包为 180 阶、1° 全球网格，不代表逐点现场测量。海洋保留海底负高程。球面起伏经过视觉夸张，局部色标增强不会提高源数据精度。Natural Earth、NOAA ETOPO、国家元数据及 OpenStreetMap 的出处与许可随包保留。

需要自行验证时，在 MATLAB 中将当前文件夹设为解压后的包根目录，然后运行：

```matlab
results = runtests('tests');
assert(all([results.Passed]));
```

完整源码、数据重建脚本及原始材料见公开仓库：
[yanynayan-cdut/matlab-global-gravity](https://github.com/yanynayan-cdut/matlab-global-gravity)。这些重建材料不是日常运行的前提。
