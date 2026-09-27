function gravity_field_app
% GLOBAL GRAVITY FIELD EXPLORER
% Base MATLAB app: rotatable globe, Miller and equirectangular maps,
% capital markers, and a height/latitude/longitude gravity calculator.
% Data/model sources are listed in SOURCES.md.

S = gravity_data();
f = uifigure('Name','Global Gravity Field Explorer','Position',[50 50 1500 850],...
    'Color',[0.97 0.97 0.97]);
gl = uigridlayout(f,[1 2]); gl.ColumnWidth={'1x',300}; gl.RowHeight={'1x'};
left = uipanel(gl,'Title','Gravity field and capitals','FontWeight','bold');
right = uipanel(gl,'Title','Gravity calculator','FontWeight','bold');
g = uigridlayout(left,[2 1]); g.RowHeight={'1x','1x'};
ax1 = uiaxes(g); ax2 = uiaxes(g); ax1.Toolbar.Visible='on'; ax2.Toolbar.Visible='on';
plot_globe(ax1,S); plot_maps(ax2,S);

rg = uigridlayout(right,[12 1]); rg.RowHeight={22,30,22,30,22,30,22,30,22,30,'1x',30};
uilabel(rg,'Text','体重 m (kg)'); mass = uieditfield(rg,'numeric','Value',70,'Limits',[0 Inf]);
uilabel(rg,'Text','海拔 h (m)'); elev = uieditfield(rg,'numeric','Value',0,'Limits',[-1000 Inf]);
uilabel(rg,'Text','首都 / 位置'); cap = uidropdown(rg,'Items',S.capitalLabels,'Value',S.capitalLabels{1});
uilabel(rg,'Text','纬度 / 经度 (deg)'); pos = uilabel(rg,'Text','');
uilabel(rg,'Text','模型'); model = uidropdown(rg,'Items',{'WGS84 + 高度修正','常数 g0'},'Value','WGS84 + 高度修正');
out = uitextarea(rg,'Editable','off','Value',{'输入参数后点击计算'},'FontName','Consolas');
btn = uibutton(rg,'Text','计算当前受力 G','ButtonPushedFcn',@calculate);
cap.ValueChangedFcn=@updatePosition; updatePosition(); calculate();

    function updatePosition(~,~)
        k=find(strcmp(S.capitalLabels,cap.Value),1); pos.Text=sprintf('%.4f° N, %.4f° E',S.capitalLat(k),S.capitalLon(k));
    end
    function calculate(~,~)
        k=find(strcmp(S.capitalLabels,cap.Value),1); lat=S.capitalLat(k); h=elev.Value;
        if strcmp(model.Value,'WGS84 + 高度修正'), gg=normal_gravity(lat,h); else, gg=9.80665; end
        G=mass.Value*gg;
        out.Value={sprintf('国家/首都: %s',cap.Value),sprintf('纬度: %.4f deg',lat),sprintf('经度: %.4f deg',S.capitalLon(k)),sprintf('体重 m: %.3f kg',mass.Value),sprintf('海拔 h: %.2f m',h),sprintf('局地重力 g: %.8f m/s^2',gg),sprintf('所受重力 G = m*g: %.6f N',G)};
    end
end

function S=gravity_data()
[lat,lon]=meshgrid(linspace(-90,90,181),linspace(-180,180,361));
% Synthetic global field: latitude dependence plus low-order longitude signal.
g=9.7803253359.*(1+0.0053024*sind(lat).^2-0.0000058*sind(2*lat).^2)+0.0008*cosd(3*lon).*cosd(lat).^2;
S.lat=lat; S.lon=lon; S.g=g;
S.capitalLabels={'中国 / 北京','美国 / 华盛顿','英国 / 伦敦','法国 / 巴黎','澳大利亚 / 堪培拉','巴西 / 巴西利亚','南非 / 比勒陀利亚','日本 / 东京','印度 / 新德里','埃及 / 开罗'};
S.capitalLat=[39.9042,38.9072,51.5074,48.8566,-35.2809,-15.7939,-25.7479,35.6762,28.6139,30.0444];
S.capitalLon=[116.4074,-77.0369,-0.1278,2.3522,149.1300,-47.8828,28.2293,139.6503,77.2090,31.2357];
end

function plot_globe(ax,S)
[x,y,z]=sphere(180); surf(ax,x,y,z,S.g(1:181,1:181),'EdgeColor','none'); hold(ax,'on');
% Capital markers (red points); labels avoid toolbox dependencies.
for k=1:numel(S.capitalLat)
 [xk,yk,zk]=sph2cart(deg2rad(S.capitalLon(k)),deg2rad(S.capitalLat(k)),1.015);
 plot3(ax,xk,yk,zk,'r.','MarkerSize',20); text(ax,xk,yk,zk,['  ' S.capitalLabels{k}],'Color','r','FontSize',8);
end
axis(ax,'equal','off'); view(ax,3); rotate3d(ax,'on'); colormap(ax,jet(256)); colorbar(ax); caxis(ax,[min(S.g(:)) max(S.g(:))]);
title(ax,'可旋转全球重力场（红点：首都）'); xlabel(ax,'来源：WGS84正常重力模型 + 低阶示意扰动'); hold(ax,'off');
end

function plot_maps(ax,S)
% Miller cylindrical projection: x=lon, y=1.25*asinh(tan(lat/2.5)).
X=S.lon; Y=rad2deg(1.25*asinh(tand(S.lat)/2.5));
surf(ax,X,Y,S.g,'EdgeColor','none'); view(ax,2); axis(ax,'tight');
hold(ax,'on'); plot(ax,S.capitalLon,rad2deg(1.25*asinh(tand(S.capitalLat)/2.5)),'r.','MarkerSize',18); hold(ax,'off');
colormap(ax,jet(256)); colorbar(ax); caxis(ax,[min(S.g(:)) max(S.g(:))]); xlabel(ax,'经度 (deg)'); ylabel(ax,'Miller 纬度'); title(ax,'Miller 圆柱展开');
end

function g=normal_gravity(phi,h)
% Somigliana WGS84 normal gravity with first-order free-air height correction.
g0=9.7803253359*(1+0.00193185265241*sind(phi).^2)./sqrt(1-0.00669437999014*sind(phi).^2);
g=g0-3.086e-6*h;
end
