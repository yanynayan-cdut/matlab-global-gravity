# MATLAB 全球重力场可视化与计算器

运行 `gravity_field_app`。界面左侧显示可旋转 3D 球面和 Miller 圆柱投影，红点为示例国家首都；右侧输入体重、海拔并选择首都，计算 `G=m*g`。

要求：MATLAB R2022b 或更高版本（仅 base MATLAB，使用 `uifigure`、`uiaxes`、`surf`、`sphere`）。色标为 MATLAB 经典 `jet` 红绿蓝色标。

模型说明：网格场是 WGS84 Somigliana 正常重力的低阶全球示意场，计算器使用 WGS84 正常重力并采用自由空气高度修正。它适合可视化与教学，不是高阶卫星重力异常产品。

## 数据出处

详见 `SOURCES.md`。联网下载 EGM2008/地理边界数据后，可在 `gravity_data` 中替换网格和首都表；当前版本自带离线可运行数据，保证无网络时仍能启动。
