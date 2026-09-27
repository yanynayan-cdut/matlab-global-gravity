# 全球重力场 MATLAB 项目

交互式全球重力可视化与人体受力计算器，使用 **ICGEM 官方 EGM2008 实测融合模型**、Natural Earth 国界与首都数据。已移除旧版人为正弦扰动和十国示例表；数据缺失时明确报错，不会换成模拟数据。

## 启动

MATLAB R2022b 或更新版本，**不需要额外 MATLAB 工具箱**。

```matlab
cd('C:/Users/ashlx/Desktop/zuoye/matlab_gravity_app')
gravity_field_app
```

启动时会让使用者确认 **197 国名单口径**。候选集合是 193 个联合国成员国，加梵蒂冈、巴勒斯坦、库克群岛、纽埃。库中保存 199 条候选记录，方便按明确要求替换名单；名单不代表主权地位判定。确定使用这一口径后可跳过确认框：

```matlab
f = gravity_field_app('CountrySet','proposed197');
```

也可传入 197 个互不重复的 ISO3 代码组成的 cellstr。代码必须出现在 `data/countries_superset.csv` 中。多首都和行政中心的选择在计算器中显示备注。

## 功能

- **大球面**独占左侧画布，拖动旋转、滚轮缩放。
- **真实国界**采用 Natural Earth 1:50m 边界；黑白双线贴合起伏曲面。半透明重力层下有同形状底层，避免背面线条透出。
- **197 个红色首都点**可点击选择；支持中文/英文国家名、中文/英文首都名及 ISO 代码搜索。
- **等值绘图**使用 MATLAB 经典 `jet` 18 级色带与等值线；不透明度和径向夸张可调，夸张为 0 时恢复球面。
- **显示量可切换**：重力扰动 `δg`（mGal）突出地区差异，总重力 `g`（m/s²）显示绝对值；同一模式中半径与颜色使用同一种量。
- **二维展开**：Miller、等距圆柱、Mercator、Mollweide 等面积投影，均有国界和可点选的首都；Mercator 限制纬度在 ±85°。
- **计算器**：输入质量 `m`（kg）与海拔 `H`（m），直接由同一 EGM2008 球谐模型在首都坐标求 `g`，计算 `G=m*g`（N），并列出参数。显示夸张不影响受力计算。

## 数据与物理含义

EGM2008 由卫星、地面、航空及卫星测高资料约束，**不是每个网格点的直接重力仪读数**。本项目从官方系数保留至 **180 阶次**，生成 **1°×1°** 网格，最短半波长约 111 km。下载地址、SHA-256、公式与限制见 [SOURCES.md](SOURCES.md) 和 [gravity_model.md](data/gravity_model.md)。

- `g` 为引力与地球自转离心加速度合成后的模。
- `δg=g−γ`；`γ` 是同一位置的 WGS84 正常重力；`1 mGal=10^-5 m/s²`。
- 网格在 WGS84 **椭球面 h=0** 上求值，不是地形表面或平均海平面。
- 函数使用椭球高 `h`；界面把海拔 `H` 近似代入并显示 `h≈H`。精密用途需用大地水准面高 `N` 做 `h=H+N` 转换。
- 径向映射为 `r=1+A*(q−q0)/max(abs(q−q0))`；`A` 为夸张系数、`q` 为所选重力量。扰动模式 `q0=0`，总重力模式 `q0` 为数值范围中点。**凹凸不是地形，也不代表实际地球变形。**
- 180 阶模型不刻画局地地形、建筑或矿体等细节，结果不等于现场测量精度。

## 函数与验证

```matlab
[g, detail] = gravity_at_location(39.9,116.4,0);
G = 70*g;
[x,y] = gravity_project([0,90],[0,45],'miller');
results = runtests('tests');
assert(all([results.Passed]));
```

计算核心直接求球谐势梯度，加入自转项。测试覆盖独立 SciPy 势函数差分参考值、两极、经度周期性、高度效应、投影公式、197 个标记、搜索、点击、质量成比例、透明度、径向映射和全部五种视图。UI 测试显式使用候选名单，不代替使用者确认口径。

数据已经随项目提供，日常运行不需要联网或 Python。可选重建需要现有 NumPy、SciPy：

```text
python scripts/rebuild_gravity_data.py
python tools/build_geodata.py
```

第二步后在 MATLAB 执行 `addpath('tools'); finalize_geodata`，原生保存 Unicode 首都结构。原始快照与许可证见 `data/`；72 MB 官方压缩包缓存在 `.cache/`，不上传 Git。

| 文件 | 用途 |
|---|---|
| `gravity_field_app.m` | 球体、二维视图和计算器 |
| `gravity_at_location.m` | EGM2008 球谐计算 |
| `gravity_project.m` | 无工具箱的投影公式 |
| `data/gravity_grid.mat` | 181×361 重力/扰动网格 |
| `data/gravity_egm2008_n180_coefficients.mat` | 真实模型系数 |
| `data/world_geodata.mat` | 国界和首都候选目录 |
| `tests/` | 物理及交互测试 |

Natural Earth 数据为公有领域；国家元数据及 OSM 补充坐标遵守随附 ODbL 许可，详见 `data/DATA_PROVENANCE.md`。
