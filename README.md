# 全球重力场 MATLAB 可视化

用 MATLAB 展示 EGM2008 全球重力场：旋转三维起伏球面、切换四种二维投影、搜索 197 国首都，并计算给定质量和高度下的重力 `G=m×g`。

![EGM2008 三维起伏球面](matlab_gravity_app/docs/globe_preview.png)

## 快速启动

MATLAB R2022b 或更新版本，无需额外 MATLAB 工具箱。数据随仓库提供，日常运行无需联网。下载或克隆仓库后，在 MATLAB 中把当前文件夹设为仓库根目录，运行：

```matlab
cd('matlab_gravity_app')
gravity_field_app
```

- 三维球面支持旋转和缩放，以 `jet` 分级色带、等值线和可调径向起伏显示重力；透明度可调，国界沿曲面绘制。
- 二维视图包括 Miller 圆柱、等距圆柱、Mercator 和 Mollweide 等面积投影。
- 197 个首都以红点标出，可在图中点击或按中英文国家名、首都名及 ISO 代码搜索。
- 右侧计算器显示质量、首都经纬度、高度、当地 `g` 和所受重力 `G`。
- 默认名单为 193 个联合国成员国，加梵蒂冈、巴勒斯坦、库克群岛、纽埃；启动无需再次确认。

![Miller 圆柱投影](matlab_gravity_app/docs/miller_preview.png)

## 模型和适用范围

重力数据来自 ICGEM 提供的官方 EGM2008 系数，是卫星、地面、航空及卫星测高资料融合模型；并非每个网格点的直接重力仪观测。本项目保留至 180 阶次，使用 1° 网格。可切换总重力 `g` 与相对 WGS84 正常重力的扰动 `δg`；计算器直接使用同一球谐模型。

球面的凹凸是重力数值的显示夸张，不是实际地形。网格在 WGS84 椭球面零高度上求值；界面将输入海拔近似为椭球高，局地地形与精密高程转换不在当前模型范围内。

详细操作、函数接口和重建方式见 [应用说明](matlab_gravity_app/README.md)。数据、公式及许可见 [来源说明](matlab_gravity_app/SOURCES.md) 和 [地理数据溯源](matlab_gravity_app/data/DATA_PROVENANCE.md)，已有 MATLAB 验证结果见 [验证记录](matlab_gravity_app/VALIDATION.md)。
