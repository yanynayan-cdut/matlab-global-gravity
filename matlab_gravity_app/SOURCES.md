# 实际使用的数据来源

这些数据已下载并用于本项目；不是尚未接入的候选来源。

## 重力

- 官方目录：ICGEM，https://icgem.gfz-potsdam.de/tom_longtime
- 实际下载：https://icgem.gfz-potsdam.de/getmodel/zip/c50128797a9cb62e936337c890e4425f03f0461d7329b09a8cc8561504465340/EGM2008.zip
- 模型：NGA EGM2008。Pavlis, Holmes, Kenyon & Factor (2012), *The development and evaluation of the Earth Gravitational Model 2008 (EGM2008)*，JGR 117, B04406，doi: **10.1029/2011JB008916**。
- 处理：保留至 180 阶次，按 WGS84 椭球位置求引力梯度并加入地球自转，生成 1° 网格。
- 原始文件 SHA-256、归一化、潮汐系统和范围：`data/gravity_provenance.json`。
- 公式、分辨率与高度约定：`data/gravity_model.md`。

## 国界、首都与许可

- Natural Earth 1:50m 国家边界：https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson
- Natural Earth 1:10m 城市点：https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_populated_places_simple.geojson
- Natural Earth 中文城市别名：https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_populated_places.geojson
- Natural Earth 许可：https://www.naturalearthdata.com/about/terms-of-use/ （公有领域）。保留源图的表示惯例，不将其作为法律主张。
- 中文国家名、ISO、首都列表：https://github.com/mledoze/countries （附带 ODbL 许可）。
- 极小首都的补充坐标与名称：OpenStreetMap / Nominatim，原始请求和返回结果随项目保留。https://www.openstreetmap.org/copyright
- 来源版本、特殊首都处理、许可证及文件校验值：`data/DATA_PROVENANCE.md`。

图下注明模型、180 阶次、1° 网格、椭球面零高度、Natural Earth 比例尺与来源站点。径向夸张和透明度只影响显示，不修改原系数或受力计算。

## 地表 / 海底高程与离心量

- 高程：NOAA NCEI ETOPO 2022 v1 Ice Surface；DOI **10.25921/fd45-gt74**。
- 产品页：https://www.ncei.noaa.gov/products/etopo-global-relief-model
- 全球显示采样自官方 60 角秒源；197 个首都独立采样自 15 角秒源。
- 海洋保留原海底负高程；极地使用冰面产品，不是冰下基岩产品。
- 高程 H 相对 EGM2008 大地水准面。配套 geoid 提供 N；计算使用 `h=H+N+Δh`。
- 离心加速度采用 WGS84 常量，`a_c=ω²(ν+h)cosφ`；个人离心力 `F_c=m*a_c`。这一项已经包含在有效重力 g 中，不再对 G 二次加减。
- WGS84 官方定义与常量：https://earth-info.nga.mil/index.php?dir=wgs84&action=wgs84
- 全球离心缓存绑定源文件 SHA-256、模型常量和高度口径；源数据或算法改变后重建。
- 完整数据引用、接口地址、采样口径、5 个海岸首都邻近陆地估计及限制见 [terrain_sources.md](data/terrain_sources.md)，每条下载响应及校验值见 `data/terrain_raw/manifest.json`。
