# 地表高程和大地水准面来源 / Terrain provenance

## 数据与许可

本项目使用 NOAA NCEI **ETOPO 2022 v1 Ice Surface** 及其配套 EGM2008
大地水准面起伏网格。它包含陆地地形、格陵兰与南极冰面，以及海域的海底地形。
“Surface”不代表把海域统一设为海平面；项目保留源数据中的负海底高程。

正式引用：NOAA National Centers for Environmental Information (2022),
*ETOPO 2022 15 Arc-Second Global Relief Model*, DOI **10.25921/fd45-gt74**。

- 产品页：<https://www.ncei.noaa.gov/products/etopo-global-relief-model>
- 用户指南 Rev 1.2：<https://www.ngdc.noaa.gov/mgg/global/relief/ETOPO2022/docs/1.2%20ETOPO%202022%20User%20Guide.pdf>
- 60 角秒地表文件：<https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/60s/60s_surface_elev_netcdf/ETOPO_2022_v1_60s_N90W180_surface.nc>
- 60 角秒大地水准面文件：<https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/60s/60s_geoid_netcdf/ETOPO_2022_v1_60s_N90W180_geoid.nc>
- 15 角秒地表分块目录：<https://www.ngdc.noaa.gov/thredds/catalog/global/ETOPO2022/15s/15s_surface_elev_netcdf/catalog.html>
- 15 角秒大地水准面分块目录：<https://www.ngdc.noaa.gov/thredds/catalog/global/ETOPO2022/15s/15s_geoid_netcdf/catalog.html>

用户指南第 4 节允许私人、学术和商业用途免费使用，并要求引用 NOAA。
配套 geoid 文件的元数据明确注明源于 NGA 的公共领域成果。
这里核对的是每个 ETOPO2022 文件的 DAS 元数据；THREDDS 目录继承的部分
介绍文字仍写 ETOPO1，不能用作当前文件的型号说明。

## 坐标与垂直基准

- 水平坐标为 WGS84 大地纬度/经度，EPSG:4326，单位为度。
- `elevationM` 和 `capitalElevationM` 是相对 **EGM2008 大地水准面**的
  重力相关高程 H，EPSG:3855，米，向上为正。该基准近似平均海平面。
- `geoidUndulationM` 和 `capitalGeoidM` 是配套大地水准面起伏 N，米。
- 按用户指南第 2.2 节，**h = H + N**，其中 h 为 WGS84 椭球高。
- 源 geoid 元数据指向 NGA `egm08_25.gtx`（2.5 角分源网格）。NOAA 将其
  重采样到 ETOPO 网格；15 角秒采样不代表 geoid 新增了 15 角秒分辨率的信息。

## 采样与局限

全球图采用 `lat=-90:90`、`lon=-180:180`。内部整数经纬度节点的值由官方
60 角秒源数据的四个相邻格点做双线性插值得到。跨日界线采用周期接缝，
最后一列复制第一列。两个极点使用最近源纬圈的每 1 度经度采样值的平均，
使同一个地理极点不因经度产生不同高度。

首都值独立从官方 **15 角秒**分块网格双线性插值得到，不从显示用 1 度图
插值。读取一个小型邻域同时保留最近源格点值、极值及海岸诊断。15 角秒
在赤道约 460 米，因此这些值不能当作建筑门口或测量控制点的精确高程。
城市坐标、混合海岸格点、狭窄岛屿，以及真实低于海面的陆地，都可能产生
负值。用户已批准 BHS、COK、MDV、MHL、NRU 五个沿海/岛屿首都采用邻近有效陆地
栅格估计：仅在 1.5 km 内搜索严格大于 0 m 的源格点，排除海平面 0 m 格点，
将最近点的高程写入 `capitalElevationM`，并记录采样坐标与距离。原始双线性
结果写入 `capitalRawElevationM`，`capitalReviewFlag` 仍为真。没有其他国家
的负高程被自动移动；这些可能是合法的低于海平面陆地。

`terrain_capital_diagnostics.json` 逐个记录查询地址、原始窗口范围、
双线性结果、最近源格点结果，以及五项经批准替代的有效值、坐标和距离。
只有这五项使用局部 6×6 格点窗口内、距离不超过 1.5 km 的严格正高程源点。
计算仍保留首都原经纬度及该坐标的 `capitalGeoidM`，并将 H 明确标作邻近
陆地高程估计。另保留采样点的 N (`capitalSampleGeoidM`) 供溯源。

## 复现与 MATLAB 接口

执行 `python scripts/rebuild_terrain_data.py` 可重建数据。它通过 NOAA 的
OPeNDAP 子集接口下载少量节点，未下载接近 1 GB 的两幅完整全球栅格。
已取得的原始响应保存在 `terrain_raw/`，每次读取先核对 SHA-256；完整缓存
可离线重建。首次运行需要 Python `requests`、NumPy、SciPy；MATLAB 运行
直接读取 `.mat`，无需 Python 或附加工具箱。

`terrain_raw/manifest.json` 记录每一条精确查询、UTC 时间、字节数及响应体
SHA-256。从完整缓存恢复的清单条目明确标注恢复状态，保存时间来自原始响应
文件；无法恢复的响应头及跳转 URL 不作推测。`terrain_provenance.json` 给出数据基准、方法、
输入和输出校验值及需要检查的首都。校验值针对解码后的 HTTP 响应体。

`terrain_data.mat` 主要字段：

| 字段 | 形状与含义 |
|---|---|
| `lat`, `lon` | 1×181、1×361，大地纬度/经度 |
| `elevationM`, `geoidUndulationM` | 181×361，H 与 N，米 |
| `capitalIso3` | 1×197 cellstr，与下列数组同序 |
| `capitalLatitude`, `capitalLongitude` | 1×197，首都大地坐标 |
| `capitalElevationM`, `capitalGeoidM` | 1×197，计算器使用的 H 与首都坐标 N，米 |
| `capitalRawElevationM` | 1×197，未移动的原始首都双线性 H |
| `capitalReviewFlag` | 1×197，原始首都高程为负的检查标记 |
| `capitalElevationIsEstimate` | 1×197，五个邻近陆地估计标记 |
| `capitalElevationSampleLatitude/Longitude` | 1×197，五项替代的 15s 栅格坐标；其他为原插值目标坐标 |
| `capitalElevationSampleDistanceM` | 1×197，距首都坐标的采样距离 |
| `capitalSampleGeoidM` | 1×197，邻近采样点的 N（保留；计算器默认使用首都坐标 N） |
| `source`, `verticalDatum`, `geoidPolicy`, `oceanPolicy` | 来源与口径说明 |

首都列表沿用项目中经确认的 197 条记录。高程文件不改变国家口径、城市名称或坐标。
