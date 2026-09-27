function fig = gravity_field_app(varargin)
%GRAVITY_FIELD_APP EGM2008 gravity, capital search and force calculator.
%   gravity_field_app opens the application. Base MATLAB R2022b or later.
%   f=gravity_field_app('Visible','off') is useful for automated validation.
parser = inputParser;
addParameter(parser,'Visible','on');
addParameter(parser,'Position',[30 40 1510 880]);
addParameter(parser,'CountrySet','');
parse(parser,varargin{:});
root = fileparts(mfilename('fullpath'));
geo = load(fullfile(root,'data','world_geodata.mat'));
field = load(fullfile(root,'data','gravity_grid.mat'));
assert(field.degree==180,'The bundled calculator uses EGM2008 degree 180; rebuild a matching grid.');
countries = geo.countries;
countrySet=parser.Results.CountrySet;
if isempty(countrySet)
    if strcmp(parser.Results.Visible,'off')
        error('gravity:CountrySet','Specify CountrySet for a noninteractive preview.');
    end
    answer=questdlg(['197 国名单采用 193 个联合国成员国 + 梵蒂冈、巴勒斯坦、库克群岛、纽埃？' ...
        '如需其他名单，请取消并指定 CountrySet 为 197 个 ISO3 代码。'], ...
        '选择国家名单口径','采用此名单','取消','取消');
    if ~strcmp(answer,'采用此名单'), fig=[]; return; end
    countrySet='proposed197';
end
if ischar(countrySet) || isstring(countrySet) && isscalar(countrySet)
    assert(strcmp(countrySet,'proposed197'),'Unknown country catalogue option.');
    ids=cellstr(geo.recommended197Iso3);
else
    ids=cellstr(countrySet);
end
assert(numel(unique(ids))==197 && all(ismember(ids,{countries.iso3})), ...
    'CountrySet must contain 197 distinct ISO3 codes in the bundled catalogue.');
countries=countries(ismember({countries.iso3},ids));
if numel(countries)~=197
    error('gravity:Catalogue','The approved catalogue must contain exactly 197 countries.');
end
lat = double(field.lat(:)); lon = double(field.lon(:)');
grav = double(field.g); disturbance = double(field.disturbance);
assert(isequal(size(grav),[numel(lat),numel(lon)]),'Invalid gravity grid dimensions.');
assert(isequal(size(grav),size(disturbance)) && all(isfinite(grav(:))) ...
    && all(isfinite(disturbance(:))),'Gravity data are incomplete. Rebuild the data; no synthetic fallback is used.');
[longrid,latgrid] = meshgrid(lon,lat);
labels = {countries.label};
selected = find(strcmp({countries.iso3},'CHN'),1);
if isempty(selected), selected=1; end
capitalLat = [countries.latitude]; capitalLon = [countries.longitude];
boundaryLat = double(geo.boundaryLatitude(:));
boundaryLon = double(geo.boundaryLongitude(:));
% A discontinuity cannot be drawn across the antimeridian in a flat map.
cuts = [false; abs(diff(boundaryLon))>180];
boundaryLat(cuts)=NaN; boundaryLon(cuts)=NaN;
currentView = [205 23];
plotHandles = struct();

fig = uifigure('Name','全球重力场 · EGM2008','Position',parser.Results.Position, ...
    'Visible',parser.Results.Visible,'Color',[0.96 0.97 0.98],'Tag','GravityApp');
outer = uigridlayout(fig,[2 2]);
outer.ColumnWidth = {'1x',340}; outer.RowHeight = {52,'1x'};
outer.Padding = [14 12 14 12]; outer.ColumnSpacing = 14;
header = uigridlayout(outer,[2 1]); header.Layout.Column=[1 2];
header.Padding=[0 0 0 0]; header.RowHeight={29,19}; header.RowSpacing=0;
uilabel(header,'Text','全球重力场  /  EGM2008','FontSize',23,'FontWeight','bold');
uilabel(header,'Text','实测融合模型 · 197 国首都 · 半透明起伏球面 · 多种二维投影','FontSize',12,'FontColor',[0.3 0.35 0.42]);
left = uigridlayout(outer,[4 1]); left.Padding=[0 0 0 0];
left.RowHeight={57,'1x',40,50}; left.RowSpacing=6;
control = uigridlayout(left,[2 6]); control.Padding=[0 0 0 0];
control.RowHeight={20,26}; control.ColumnWidth={65,160,65,'1x',65,'1x'};
uilabel(control,'Text','显示量');
mode = uidropdown(control,'Items',{'重力扰动 δg (mGal)','总重力 g (m/s²)'}, ...
    'ItemsData',{'disturbance','gravity'},'Value','disturbance','Tag','FieldMode');
uilabel(control,'Text','径向夸张');
relief = uislider(control,'Limits',[0 0.3],'Value',0.16, ...
    'MajorTicks',[],'MinorTicks',[],'Tag','Relief');
uilabel(control,'Text','不透明度');
opacity = uislider(control,'Limits',[0.15 1],'Value',0.78, ...
    'MajorTicks',[],'MinorTicks',[],'Tag','Opacity');
displayNote = uilabel(control,'Text','','FontSize',11,'FontColor',[0.32 0.36 0.4]);
displayNote.Layout.Column=[1 6];
tabs = uitabgroup(left,'Tag','ProjectionTabs');
tabTitles = {'三维球面','Miller 圆柱','等距圆柱','Mercator 圆柱','Mollweide 等面积'};
projections = {'globe','miller','equirectangular','mercator','mollweide'};
tabList = gobjects(1,5); axesList=gobjects(1,5);
for k=1:5
    tabList(k)=uitab(tabs,'Title',tabTitles{k},'Tag',projections{k});
    panel=uigridlayout(tabList(k),[1 1]); panel.Padding=[8 10 37 23];
    axesList(k)=uiaxes(panel,'Tag',['Axes_' projections{k}]);
    axesList(k).FontSize=11;
    axesList(k).Toolbar.Visible='on';
end
selectionLabel=uilabel(left,'Text','','FontSize',12,'WordWrap','on','Tag','SelectionLabel');
sourceLabel=uilabel(left,'Text',sprintf(['数据：ICGEM / NGA EGM2008，180 阶次，1° 网格，WGS84 椭球面 h=0；国界：Natural Earth 1:50m。\n' ...
    '来源：icgem.gfz-potsdam.de | naturalearthdata.com | github.com/mledoze/countries；凹凸为重力数值夸张，不是地形。']), ...
    'FontSize',10,'WordWrap','on','FontColor',[0.33 0.37 0.42],'Tag','Sources'); %#ok<NASGU>

side = uipanel(outer,'Title','首都定位与重力计算','FontWeight','bold','BackgroundColor',[1 1 1]);
right = uigridlayout(side,[15 1]); right.Padding=[12 10 12 10]; right.RowSpacing=6;
right.RowHeight={20,30,20,120,42,23,30,23,30,35,36,'1x',27,27,24};
uilabel(right,'Text','搜索国家 / 首都 / ISO 代码','FontWeight','bold');
search = uieditfield(right,'text','Placeholder','中国 / Beijing / CHN', ...
    'Tag','CountrySearch','ValueChangingFcn',@searchChanging,'ValueChangedFcn',@searchChanged);
countLabel=uilabel(right,'Text','197 / 197 个国家','Tag','CountryCount');
countryList=uilistbox(right,'Items',labels,'ItemsData',1:197,'Value',selected, ...
    'Tag','CountryList','ValueChangedFcn',@chooseCountry);
coordinates=uilabel(right,'Text','','WordWrap','on','Tag','Coordinates');
uilabel(right,'Text','质量 m (kg，日常所说的体重)');
mass=uieditfield(right,'numeric','Value',70,'Limits',[0 100000],'Tag','Mass', ...
    'ValueChangedFcn',@calculate);
uilabel(right,'Text','海拔 H (m)');
height=uieditfield(right,'numeric','Value',0,'Limits',[-500 10000],'Tag','Altitude', ...
    'ValueChangedFcn',@calculate);
uilabel(right,'Text','近似取椭球高 h = H，未加入大地水准面高 N。','WordWrap','on','FontSize',11);
forceLabel=uilabel(right,'Text','','FontSize',22,'FontWeight','bold','FontColor',[0.05 0.29 0.5],'Tag','Force');
results=uitextarea(right,'Editable','off','FontSize',11,'Tag','Calculation');
uibutton(right,'Text','计算 G = m × g','ButtonPushedFcn',@calculate,'Tag','Calculate');
uibutton(right,'Text','定位所选首都 / 重置视角','ButtonPushedFcn',@focusCapital);
status=uilabel(right,'Text','红点可点击选择；拖动球面旋转。','FontSize',11,'Tag','Status');

mode.ValueChangedFcn=@refreshPlot;
relief.ValueChangedFcn=@refreshPlot;
opacity.ValueChangedFcn=@refreshPlot;
tabs.SelectionChangedFcn=@refreshPlot;
updateCountry(); refreshPlot(); calculate();

    function searchChanging(~,event)
        filterCountries(event.Value);
    end
    function searchChanged(~,~)
        filterCountries(search.Value);
    end
    function filterCountries(query)
        query=lower(strtrim(char(query)));
        matches=arrayfun(@(c)isempty(query)||contains(lower(c.search),query) ...
            ||contains(lower(c.label),query),countries);
        ids=find(matches);
        countLabel.Text=sprintf('%d / 197 个国家',numel(ids));
        if isempty(ids)
            countryList.Items={'没有匹配项'}; countryList.ItemsData=0; countryList.Value=0;
            return
        end
        countryList.Items=labels(ids); countryList.ItemsData=ids;
        if ismember(selected,ids)
            countryList.Value=selected;
        else
            countryList.Value=ids(1);
            selected=ids(1); updateCountry(); updateMarker(); calculate();
        end
    end
    function chooseCountry(~,~)
        if countryList.Value==0, return; end
        selectCapital(countryList.Value,false);
    end
    function selectCapital(index,fromMap)
        selected=index;
        if fromMap
            search.Value=''; filterCountries(''); countryList.Value=index;
        end
        updateCountry(); updateMarker(); calculate();
    end
    function updateCountry()
        c=countries(selected);
        coordinates.Text=sprintf('%s\n纬度 %.4f°，经度 %.4f°',capitalName(c),c.latitude,c.longitude);
        selectionLabel.Text=sprintf('所选：%s  |  %s  |  纬度 %.4f°，经度 %.4f°', ...
            c.countryZh,capitalName(c),c.latitude,c.longitude);
    end
    function calculate(~,~)
        c=countries(selected);
        try
            [local,detail]=gravity_at_location(c.latitude,c.longitude,height.Value);
            force=mass.Value*local;
            assert(isfinite(force)&&force>=0,'Invalid force from model.');
            forceLabel.Text=sprintf('G = %.4f N',force);
            results.Value={sprintf('%s / %s',c.countryZh,capitalName(c)), ...
                sprintf('φ = %.5f°；λ = %.5f°',c.latitude,c.longitude), ...
                sprintf('m = %.3f kg；H = %.2f m',mass.Value,height.Value), ...
                sprintf('g = %.8f m/s²',local), ...
                sprintf('正常重力 γ = %.8f m/s²',detail.normalGravity), ...
                sprintf('δg = %.3f mGal',detail.disturbance*1e5), ...
                'EGM2008 180 阶；包含地球自转', ...
                'h≈H；结果为模型估计，非当地直接观测。', c.notes};
            status.Text='点击红点选择首都；拖动球面旋转。';
            fig.UserData=struct('iso3',c.iso3,'g',local,'force',force,'mass',mass.Value, ...
                'height',height.Value,'latitude',c.latitude,'longitude',c.longitude);
        catch errorInfo
            forceLabel.Text='计算失败'; results.Value={errorInfo.message};
            status.Text='请检查数据文件；不会退回模拟重力场。';
        end
    end
    function focusCapital(~,~)
        tabs.SelectedTab=tabList(1);
        currentView=[countries(selected).longitude+90 countries(selected).latitude];
        refreshPlot();
    end
    function refreshPlot(~,~)
        if isfield(plotHandles,'axes') && isgraphics(plotHandles.axes) ...
                && strcmp(plotHandles.projection,'globe')
            if ~isequal(plotHandles.axes.View,currentView) && nargin>0
                currentView=plotHandles.axes.View;
            end
        end
        index=find(tabList==tabs.SelectedTab,1);
        a=axesList(index); projection=projections{index};
        if strcmp(mode.Value,'gravity')
            values=grav; unit='g (m/s²)'; center=(min(values(:))+max(values(:)))/2;
        else
            values=disturbance*1e5; unit='δg (mGal)'; center=0;
        end
        span=max(abs(values(:)-center));
        limits=[min(values(:)) max(values(:))];
        levels=linspace(limits(1),limits(2),19);
        radii=1+relief.Value*(values-center)/span;
        displayNote.Text=sprintf('等值分色：18 级  |  r = 1 + %.2f × (数值 − %.4g) / %.4g  |  不透明度 %.0f%%', ...
            relief.Value,center,span,100*opacity.Value);
        if isfield(plotHandles,'axes') && isgraphics(plotHandles.axes)
            plotHandles.axes.Interactions=[];
        end
        cla(a,'reset'); a.Tag=['Axes_' projection]; hold(a,'on');
        a.Toolbar.Visible='on'; a.FontSize=11; a.Color=[0.98 0.99 1];
        if strcmp(projection,'globe')
            drawGlobe(a,values,radii,levels);
        else
            drawMap(a,values,levels,projection);
        end
        colormap(a,jet(18)); clim(a,limits);
        cb=colorbar(a); cb.Label.String=unit;
        cb.FontSize=10;
        title(a,sprintf('EGM2008 · %s',unit),'FontSize',14,'FontWeight','normal');
        hold(a,'off');
        plotHandles.axes=a; plotHandles.projection=projection;
        plotHandles.radii=radii;
        updateMarker();
    end
    function drawGlobe(a,values,radii,levels)
        % A matching opaque underlay suppresses far-side lines. Alpha then
        % blends the measured field with the base, without hiding borders.
        [sx,sy,sz]=xyz(latgrid,longrid,radii-0.003);
        surf(a,sx,sy,sz,'FaceColor',[0.78 0.82 0.86], ...
            'EdgeColor','none','HitTest','off','PickableParts','none','Tag','OpaqueCore');
        [x,y,z]=xyz(latgrid,longrid,radii);
        surf(a,x,y,z,values,'EdgeColor','none','FaceAlpha',opacity.Value, ...
            'FaceColor','interp','HitTest','off','PickableParts','none','Tag','GravitySurface');
        contourPaths=contourc(lon,lat,values,levels(4:3:end-3));
        [clon,clat]=contourLines(contourPaths);
        rr=interp2(lon,lat,radii,clon,clat,'linear')+0.004;
        [x,y,z]=xyz(clat,clon,rr);
        plot3(a,x,y,z,'Color',[0.42 0.49 0.52],'LineWidth',0.3, ...
            'HitTest','off','PickableParts','none','Tag','GravityContours');
        rr=interp2(lon,lat,radii,boundaryLon,boundaryLat,'linear')+0.009;
        [x,y,z]=xyz(boundaryLat,boundaryLon,rr);
        plot3(a,x,y,z,'Color',[1 1 1],'LineWidth',2.2,'HitTest','off','PickableParts','none');
        plot3(a,x,y,z,'Color',[0.05 0.07 0.1],'LineWidth',1.0, ...
            'HitTest','off','PickableParts','none','Tag','CountryBoundaries');
        rr=interp2(lon,lat,radii,capitalLon,capitalLat,'linear')+0.016;
        [x,y,z]=xyz(capitalLat,capitalLon,rr);
        plotHandles.capitalXYZ=[x(:) y(:) z(:)];
        plotHandles.capitals=scatter3(a,x,y,z,20,[0.95 0.05 0.09],'filled', ...
            'MarkerEdgeColor',[0.4 0 0],'LineWidth',0.3,'ButtonDownFcn',@pickCapital,'Tag','CapitalMarkers');
        plotHandles.highlight=plot3(a,NaN,NaN,NaN,'o','MarkerSize',12, ...
            'MarkerEdgeColor',[0.05 0.05 0.05],'LineWidth',2,'HitTest','off','Tag','SelectedCapital');
        axis(a,'equal','off');
        rlim=1+relief.Value+0.035;
        xlim(a,[-rlim rlim]); ylim(a,[-rlim rlim]); zlim(a,[-rlim rlim]);
        view(a,currentView);
        a.Projection='orthographic';
        % Explicit camera scale prevents a total-g prolate shape from being
        % cropped after switching from a map or a previous relief mode.
        a.DataAspectRatio=[1 1 1];
        a.PlotBoxAspectRatio=[1 1 1];
        a.CameraTarget=[0 0 0];
        az=currentView(1); el=currentView(2);
        direction=[sind(az)*cosd(el),-cosd(az)*cosd(el),sind(el)];
        a.CameraPosition=direction*(rlim/tand(10));
        a.CameraUpVector=[0 0 1];
        a.CameraViewAngle=20;
        axis(a,'vis3d');
        a.Interactions=[rotateInteraction zoomInteraction];
    end
    function drawMap(a,values,levels,projection)
        validRows=true(size(lat));
        if strcmp(projection,'mercator'), validRows=abs(lat)<=85; end
        [x,y]=gravity_project(longrid(validRows,:),latgrid(validRows,:),projection);
        contourf(a,x,y,values(validRows,:),levels,'LineColor','none','FaceAlpha',opacity.Value,'Tag','GravityContours');
        [x,y]=gravity_project(boundaryLon,boundaryLat,projection);
        if strcmp(projection,'mercator'), x(abs(boundaryLat)>85)=NaN; y(abs(boundaryLat)>85)=NaN; end
        plot(a,x,y,'Color',[1 1 1],'LineWidth',1.6,'HitTest','off','PickableParts','none');
        plot(a,x,y,'Color',[0.07 0.08 0.1],'LineWidth',0.6, ...
            'HitTest','off','PickableParts','none','Tag','CountryBoundaries');
        [x,y]=gravity_project(capitalLon,capitalLat,projection);
        plotHandles.capitalXYZ=[x(:) y(:) zeros(numel(x),1)];
        plotHandles.capitals=scatter(a,x,y,18,[0.95 0.05 0.09],'filled', ...
            'MarkerEdgeColor',[0.4 0 0],'LineWidth',0.3,'ButtonDownFcn',@pickCapital,'Tag','CapitalMarkers');
        plotHandles.highlight=plot(a,NaN,NaN,'o','MarkerSize',12, ...
            'MarkerEdgeColor',[0.05 0.05 0.05],'LineWidth',2,'HitTest','off','Tag','SelectedCapital');
        axis(a,'equal'); axis(a,'tight'); box(a,'on');
        a.XTick=[]; a.YTick=[];
        if strcmp(projection,'mercator')
            xlabel(a,'Mercator：纬度限制在 ±85°，两极不在图内');
        else
            xlabel(a,'红点：首都；黑白线：国家边界；细等值线：重力');
        end
        a.Interactions=[panInteraction zoomInteraction];
    end
    function pickCapital(~,event)
        point=event.IntersectionPoint;
        if strcmp(plotHandles.projection,'globe')
            delta=plotHandles.capitalXYZ-point;
        else
            delta=plotHandles.capitalXYZ(:,1:2)-point(1:2);
        end
        [~,nearest]=min(sum(delta.^2,2));
        selectCapital(nearest,true);
    end
    function updateMarker()
        if ~isfield(plotHandles,'highlight') || ~isgraphics(plotHandles.highlight), return; end
        point=plotHandles.capitalXYZ(selected,:);
        set(plotHandles.highlight,'XData',point(1),'YData',point(2));
        if strcmp(plotHandles.projection,'globe'), plotHandles.highlight.ZData=point(3); end
    end
end

function [x,y,z]=xyz(lat,lon,r)
x=r.*cosd(lat).*cosd(lon); y=r.*cosd(lat).*sind(lon); z=r.*sind(lat);
end

function name=capitalName(country)
name=country.capital;
if isfield(country,'capitalZh') && ~isempty(country.capitalZh)
    name=sprintf('%s / %s',country.capitalZh,country.capital);
end
end

function [lon,lat]=contourLines(matrix)
parts={}; k=1;
while k<size(matrix,2)
    n=matrix(2,k);
    parts{end+1}=[matrix(:,k+1:k+n) nan(2,1)]; %#ok<AGROW>
    k=k+n+1;
end
if isempty(parts), lon=NaN; lat=NaN; return; end
lines=[parts{:}]; lon=lines(1,:); lat=lines(2,:);
end
