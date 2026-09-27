function fig = gravity_field_app(varargin)
%GRAVITY_FIELD_APP Gravity, terrain, rotation fields and capital calculator.
%   gravity_field_app opens the application. Base MATLAB R2022b or later.
%   f=gravity_field_app('Visible','off') is useful for automated validation.
%   gravity_field_app('RenderQuality','fast') favors smooth interaction.
%   Quality only changes display geometry, never the gravity calculator.
parser = inputParser;
addParameter(parser,'Visible','on');
addParameter(parser,'Position',[30 40 1510 880]);
% Approved catalogue: UN193 + Holy See, Palestine, Cook Islands and Niue.
addParameter(parser,'CountrySet','un197');
addParameter(parser,'RenderQuality','balanced');
parse(parser,varargin{:});
root = fileparts(mfilename('fullpath'));
geo = load(fullfile(root,'data','world_geodata.mat'));
field = load(fullfile(root,'data','gravity_grid.mat'));
[environment,environmentCache]=load_surface_environment();
assert(field.degree==180,'The bundled calculator uses EGM2008 degree 180; rebuild a matching grid.');
countries = geo.countries;
countrySet=parser.Results.CountrySet;
if isempty(countrySet), countrySet='un197'; end
if ischar(countrySet) || isstring(countrySet) && isscalar(countrySet)
    assert(any(strcmp(countrySet,{'un197','proposed197'})),'Unknown country catalogue option.');
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
labels = {countries.label};
selected = find(strcmp({countries.iso3},'CHN'),1);
if isempty(selected), selected=1; end
capitalLat = [countries.latitude]; capitalLon = [countries.longitude];
[foundCapital,capitalEnvironmentIndex]=ismember({countries.iso3},cellstr(environment.capitalIso3));
assert(all(foundCapital),'Terrain data must include every selected capital.');
assert(isequal(double(environment.lat(:)),lat) && isequal(double(environment.lon(:)'),lon), ...
    'Terrain and gravity display grids must match.');
boundaryLat = double(geo.boundaryLatitude(:));
boundaryLon = double(geo.boundaryLongitude(:));
% A discontinuity cannot be drawn across the antimeridian in a flat map.
cuts = [false; abs(diff(boundaryLon))>180];
boundaryLat(cuts)=NaN; boundaryLon(cuts)=NaN;
currentView = [205 23];
plotHandles = struct();
scenes=cell(1,5);
geometryCache=struct(); fieldCache=struct();

fig = uifigure('Name','全球重力场 · EGM2008 / ETOPO 2022','Position',parser.Results.Position, ...
    'Visible',parser.Results.Visible,'Color',[0.96 0.97 0.98],'Tag','GravityApp');
outer = uigridlayout(fig,[2 2]);
outer.ColumnWidth = {'1x',340}; outer.RowHeight = {52,'1x'};
outer.Padding = [14 12 14 12]; outer.ColumnSpacing = 14;
header = uigridlayout(outer,[2 1]); header.Layout.Column=[1 2];
header.Padding=[0 0 0 0]; header.RowHeight={29,19}; header.RowSpacing=0;
uilabel(header,'Text','全球重力场与地表环境','FontSize',23,'FontWeight','bold');
uilabel(header,'Text','EGM2008 · NOAA ETOPO 2022 · 地表高程与离心量 · 197 国首都','FontSize',12,'FontColor',[0.3 0.35 0.42]);
left = uigridlayout(outer,[4 1]); left.Padding=[0 0 0 0];
left.RowHeight={57,'1x',40,50}; left.RowSpacing=6;
control = uigridlayout(left,[2 6]); control.Padding=[0 0 0 0];
control.RowHeight={20,26}; control.ColumnWidth={65,160,65,'1x',65,'1x'};
uilabel(control,'Text','显示量');
mode = uidropdown(control,'Items',{'重力扰动 δg (mGal)','总重力 g (m/s²)','地表 / 海底高程 (m)','离心力 / 加速度'}, ...
    'ItemsData',{'disturbance','gravity','elevation','centrifugal'},'Value','disturbance','Tag','FieldMode');
uilabel(control,'Text','径向夸张');
relief = uislider(control,'Limits',[0 0.3],'Value',0.16, ...
    'MajorTicks',[],'MinorTicks',[],'Tag','Relief');
uilabel(control,'Text','不透明度');
opacity = uislider(control,'Limits',[0.15 1],'Value',0.78, ...
    'MajorTicks',[],'MinorTicks',[],'Tag','Opacity');
uilabel(control,'Text','显示质量');
quality=uidropdown(control,'Items',{'流畅 · 4°','均衡 · 2°','精细 · 1°'}, ...
    'ItemsData',{'fast','balanced','fine'}, ...
    'Value',validatestring(parser.Results.RenderQuality,{'fast','balanced','fine'}), ...
    'Tag','RenderQuality','Tooltip','只改变显示细节；原始数据和180阶重力计算不变。流畅档用预合成透明效果。');
uilabel(control,'Text','离心图单位');
centrifugalUnit=uidropdown(control,'Items',{'加速度 (m/s²)','当前质量离心力 (N)'}, ...
    'ItemsData',{'acceleration','force'},'Value','acceleration','Enable','off','Tag','CentrifugalUnit', ...
    'Tooltip','全球离心图在源地表/海底高程上计算；个人相对高程只影响右侧计算器。');
displayNote = uilabel(control,'Text','','FontSize',10,'WordWrap','on','FontColor',[0.32 0.36 0.4]);
displayNote.Layout.Column=[5 6];
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
sourceLabel=uilabel(left,'Text','','FontSize',10,'WordWrap','on', ...
    'FontColor',[0.33 0.37 0.42],'Tag','Sources');

side = uipanel(outer,'Title','首都定位与重力计算','FontWeight','bold','BackgroundColor',[1 1 1]);
right = uigridlayout(side,[16 1]); right.Padding=[12 10 12 10]; right.RowSpacing=6;
right.RowHeight={20,30,20,100,76,23,30,23,30,34,32,40,'1x',27,27,24};
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
uilabel(right,'Text','相对高程 Δh (m，相对当地地表)','Tag','AltitudeLabel');
height=uieditfield(right,'numeric','Value',0,'Limits',[-500 10000],'Tag','Altitude', ...
    'ValueChangedFcn',@calculate,'Tooltip','0 表示位于当地地表；正值为地表以上，负值为地下。');
uilabel(right,'Text','计算高度：h = 地表海拔 + 相对高程 + 大地水准面高 N。','WordWrap','on','FontSize',11);
forceLabel=uilabel(right,'Text','','FontSize',22,'FontWeight','bold','FontColor',[0.05 0.29 0.5],'Tag','Force');
centrifugalLabel=uilabel(right,'Text','','FontSize',12,'FontWeight','bold', ...
    'FontColor',[0.36 0.2 0.08],'Tag','CentrifugalForce');
results=uitextarea(right,'Editable','off','FontSize',11,'Tag','Calculation');
uibutton(right,'Text','计算 G = m × g','ButtonPushedFcn',@calculate,'Tag','Calculate');
uibutton(right,'Text','定位所选首都 / 重置视角','ButtonPushedFcn',@focusCapital);
status=uilabel(right,'Text','红点可点击选择；拖动球面旋转。','FontSize',11,'Tag','Status');

mode.ValueChangedFcn=@refreshPlot;
relief.ValueChangedFcn=@refreshPlot;
opacity.ValueChangedFcn=@refreshPlot;
quality.ValueChangedFcn=@refreshPlot;
centrifugalUnit.ValueChangedFcn=@refreshPlot;
tabs.SelectionChangedFcn=@refreshPlot;
setappdata(fig,'EnvironmentCache',environmentCache);
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
        exactCodes=strcmpi({countries.iso3},query)|strcmpi({countries.iso2},query);
        if any(exactCodes), matches=exactCodes; end
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
        e=capitalEnvironmentIndex(selected);
        [samplingNote,~,~]=capitalSamplingNote(e);
        coordinates.Text=sprintf('%s\n纬度 %.4f°，经度 %.4f°\n地表海拔 H_s = %.1f m（ETOPO）\n%s', ...
            capitalName(c),c.latitude,c.longitude,environment.capitalElevationM(e),samplingNote);
        coordinates.Tooltip=samplingNote;
        selectionLabel.Text=sprintf('所选：%s  |  %s  |  纬度 %.4f°，经度 %.4f°', ...
            c.countryZh,capitalName(c),c.latitude,c.longitude);
    end
    function [note,distance,nearbyEstimate]=capitalSamplingNote(e)
        distance=0; nearbyEstimate=false;
        if isfield(environment,'capitalElevationIsEstimate')
            nearbyEstimate=logical(environment.capitalElevationIsEstimate(e));
        end
        if nearbyEstimate
            distance=double(environment.capitalElevationSampleDistanceM(e));
            note=sprintf('邻近陆地估计 · 采样距离 %.0f m',distance);
        else
            note='15″栅格插值估计 · 非现场测量';
        end
    end
    function calculate(~,~)
        c=countries(selected);
        try
            e=capitalEnvironmentIndex(selected);
            surfaceElevation=environment.capitalElevationM(e);
            geoid=environment.capitalGeoidM(e);
            [samplingNote,samplingDistance,nearbyEstimate]=capitalSamplingNote(e);
            totalAltitude=surfaceElevation+height.Value;
            ellipsoidalHeight=environment.capitalHSurface(e)+height.Value;
            [local,detail]=gravity_at_location(c.latitude,c.longitude,ellipsoidalHeight);
            centrifugalAcceleration=environment.capitalAcSurface(e)+environment.capitalAcHeightSlope(e)*height.Value;
            centrifugalForce=mass.Value*centrifugalAcceleration;
            force=mass.Value*local;
            assert(isfinite(force)&&force>=0,'Invalid force from model.');
            forceLabel.Text=sprintf('G = %.4f N',force);
            centrifugalLabel.Text=sprintf('离心加速度 a_c = %.9f m/s²\n离心力 F_c = %.6f N', ...
                centrifugalAcceleration,centrifugalForce);
            results.Value={sprintf('%s / %s',c.countryZh,capitalName(c)), ...
                sprintf('φ = %.5f°；λ = %.5f°',c.latitude,c.longitude), ...
                sprintf('m = %.3f kg；相对高程 Δh = %.2f m',mass.Value,height.Value), ...
                sprintf('地表海拔 H_s = %.2f m；N = %.2f m',surfaceElevation,geoid), ...
                samplingNote, ...
                sprintf('总海拔 H = %.2f m；椭球高 h = %.2f m',totalAltitude,ellipsoidalHeight), ...
                sprintf('g = %.8f m/s²',local), ...
                sprintf('正常重力 γ = %.8f m/s²',detail.normalGravity), ...
                sprintf('δg = %.3f mGal',detail.disturbance*1e5), ...
                sprintf('离心加速度 a_c = %.9f m/s²',centrifugalAcceleration), ...
                sprintf('离心力 F_c = %.6f N（向外远离自转轴）',centrifugalForce), ...
                'g 已含离心项，G=m*g 不再重复加减 F_c。', ...
                '地表高程为栅格估计，不能代替现场测量。', c.notes};
            status.Text='点击红点选择首都；拖动球面旋转。';
            fig.UserData=struct('iso3',c.iso3,'g',local,'force',force,'mass',mass.Value, ...
                'height',height.Value,'relativeHeight',height.Value,'surfaceElevation',surfaceElevation, ...
                'geoidUndulation',geoid,'altitude',totalAltitude,'ellipsoidalHeight',ellipsoidalHeight, ...
                'centrifugalAcceleration',centrifugalAcceleration,'centrifugalForce',centrifugalForce, ...
                'elevationSampleDistance',samplingDistance,'elevationNearbyEstimate',nearbyEstimate, ...
                'latitude',c.latitude,'longitude',c.longitude);
            if strcmp(mode.Value,'centrifugal') && strcmp(centrifugalUnit.Value,'force')
                refreshPlot();
            end
        catch errorInfo
            forceLabel.Text='计算失败'; results.Value={errorInfo.message};
            centrifugalLabel.Text='离心力计算失败';
            status.Text='请检查数据文件；不会退回模拟重力场。';
        end
    end
    function focusCapital(~,~)
        tabs.SelectedTab=tabList(1);
        currentView=[countries(selected).longitude+90 countries(selected).latitude];
        refreshPlot();
        fitCamera(axesList(1),1+radialAmplitude()+0.035);
    end
    function amplitude=radialAmplitude()
        amplitude=relief.Value;
        if any(strcmp(mode.Value,{'gravity','centrifugal'}))
            % Total g has a strong smooth latitude gradient. Apply only 10%
            % of the slider amplitude (at most +/-3%) to retain a globe.
            % The radial ordering and colors still use true total gravity.
            amplitude=0.1*amplitude;
        elseif strcmp(mode.Value,'elevation')
            amplitude=0.25*amplitude;
        end
    end
    function D=getRenderData()
        key=[quality.Value '_' mode.Value];
        mapMass=NaN;
        if strcmp(mode.Value,'centrifugal')
            key=[key '_' centrifugalUnit.Value];
            if strcmp(centrifugalUnit.Value,'force'), mapMass=mass.Value; end
        end
        if isfield(fieldCache,key)
            D=fieldCache.(key);
            if isequaln(D.mapMass,mapMass), return; end
        end
        q=quality.Value;
        if ~isfield(geometryCache,q)
            geometryCache.(q)=gravity_display_geometry(lat,lon,grav,boundaryLat,boundaryLon,q);
        end
        geometry=geometryCache.(q);
        switch mode.Value
            case 'gravity'
                fullValues=grav; unit='g (m/s²)'; center=(min(grav(:))+max(grav(:)))/2;
                plotTitle='EGM2008 · 总重力';
            case 'disturbance'
                fullValues=disturbance*1e5; unit='δg (mGal)'; center=0;
                plotTitle='EGM2008 · 重力扰动';
            case 'elevation'
                fullValues=double(environment.elevationM); unit='地表 / 海底高程 (m)'; center=0;
                plotTitle='NOAA ETOPO 2022 · 地表 / 海底高程';
            case 'centrifugal'
                fullValues=double(environment.acSurface);
                unit='a_c (m/s²)'; plotTitle='地表 / 海底离心加速度';
                if strcmp(centrifugalUnit.Value,'force')
                    fullValues=fullValues*mapMass; unit='F_c (N)';
                    plotTitle=sprintf('地表 / 海底离心力 · m = %.4g kg',mapMass);
                end
                center=(min(fullValues(:))+max(fullValues(:)))/2;
        end
        dataKey=key;
        if isfinite(mapMass), dataKey=sprintf('%s_m%.17g',key,mapMass); end
        limits=[min(fullValues(:)) max(fullValues(:))];
        span=max(abs(fullValues(:)-center));
        if span==0
            % A zero-mass force map is a real constant-zero field. A narrow
            % color interval keeps contourf/colorbar valid without fake data.
            span=1; limits=center+[-1 1]*1e-6;
        end
        D=struct('key',dataKey,'quality',q,'lat',geometry.lat,'lon',geometry.lon, ...
            'values',fullValues(geometry.rowIndex,geometry.columnIndex),'unit',unit, ...
            'center',center,'span',span,'limits',limits,'mapMass',mapMass,'title',plotTitle, ...
            'boundaryLat',geometry.boundaryLatitude,'boundaryLon',geometry.boundaryLongitude, ...
            'stats',geometry.metadata,'stride',geometry.stride);
        D.levels=linspace(D.limits(1),D.limits(2),19);
        D.normalized=(D.values-D.center)/D.span;
        [D.longrid,D.latgrid]=meshgrid(D.lon,D.lat);
        [D.gx,D.gy,D.gz]=xyz(D.latgrid,D.longrid,1);
        [D.bx,D.by,D.bz]=xyz(D.boundaryLat,D.boundaryLon,1);
        D.bn=interp2(D.lon,D.lat,D.normalized,D.boundaryLon,D.boundaryLat,'linear');
        [D.cx,D.cy,D.cz]=xyz(capitalLat,capitalLon,1);
        D.cn=interp2(D.lon,D.lat,D.normalized,capitalLon,capitalLat,'linear');
        if strcmp(q,'fast'), contourLevels=D.levels([7 10 13]);
        else, contourLevels=D.levels(4:3:end-3); end
        matrix=contourc(D.lon,D.lat,D.values,contourLevels);
        [contourLon,contourLat]=contourLines(matrix);
        [D.tx,D.ty,D.tz]=xyz(contourLat,contourLon,1);
        D.tn=interp2(D.lon,D.lat,D.normalized,contourLon,contourLat,'linear');
        D.stats.contourVertices=nnz(isfinite(contourLon));
        fieldCache.(key)=D;
    end
    function refreshPlot(~,~)
        if strcmp(mode.Value,'centrifugal')
            centrifugalUnit.Enable='on';
        else
            centrifugalUnit.Enable='off';
        end
        index=find(tabList==tabs.SelectedTab,1);
        D=getRenderData();
        if isempty(scenes{index}), scenes{index}=createScene(index,D); end
        scene=scenes{index};
        newField=~strcmp(scene.key,D.key);
        newRelief=scene.relief~=relief.Value;
        newOpacity=scene.opacity~=opacity.Value;
        if newField || (newRelief && strcmp(scene.projection,'globe'))
            scene=updateGeometry(scene,D);
        end
        if newField
            clim(scene.axes,D.limits);
            scene.colorbar.Label.String=D.unit;
            title(scene.axes,D.title,'FontSize',14,'FontWeight','normal');
        end
        if newField || newOpacity
            alpha=opacity.Value;
            if strcmp(D.quality,'fast')
                % The old opaque underlay hid the interior anyway. Blend its
                % color in advance to avoid per-frame transparency sorting.
                palette=alpha*jet(18)+(1-alpha)*[0.78 0.82 0.86];
                scene.field.FaceAlpha=1;
                scene.halo.Visible='off';
                if strcmp(scene.projection,'globe'), scene.core.Visible='off'; end
            else
                palette=jet(18);
                scene.field.FaceAlpha=alpha;
                scene.halo.Visible='on';
                if strcmp(scene.projection,'globe'), scene.core.Visible='on'; end
            end
            colormap(scene.axes,palette);
        end
        scene.key=D.key; scene.relief=relief.Value; scene.opacity=opacity.Value;
        scenes{index}=scene; plotHandles=scene;
        updateMarker();
        transparency='真透明';
        if strcmp(D.quality,'fast'), transparency='预合成透明'; end
        displayNote.Text=sprintf('%d° · 起伏 ±%.1f%% · %s',D.stride,100*radialAmplitude(),transparency);
        displayNote.Tooltip=sprintf('原数据1°；显示%d°；国界%d点。显示起伏不改变物理数据。', ...
            D.stride,D.stats.displayBoundaryVertices);
        switch mode.Value
            case {'gravity','centrifugal'}
                relief.Tooltip='实际半径幅度为滑块值的10%，最大±3%；避免大尺度梯度使球面整体拉长。';
            case 'elevation'
                relief.Tooltip='实际半径幅度为滑块值的25%，最大±7.5%；颜色是原高程，半径是夸张的地形示意。';
            otherwise
                relief.Tooltip='重力扰动：实际半径幅度等于滑块值，最大±30%；用于夸张地区差异。';
        end
        updateSources();
        stats=D.stats; stats.quality=D.quality; stats.key=D.key;
        stats.projection=scene.projection; stats.sourceGridSpacing=1;
        stats.displayGridSpacing=D.stride;
        stats.radialAmplitude=radialAmplitude();
        stats.fitRadius=1+stats.radialAmplitude+0.035;
        stats.fieldMode=mode.Value; stats.centrifugalUnit=centrifugalUnit.Value;
        setappdata(fig,'RenderStats',stats);
    end
    function updateSources()
        switch mode.Value
            case 'elevation'
                sourceLabel.Text=sprintf(['高程：NOAA NCEI ETOPO 2022 Ice Surface，陆地海拔与海底负高程；1°显示采样，径向地形作夸张。\n' ...
                    '来源：www.ncei.noaa.gov/products/etopo-global-relief-model；国界：Natural Earth 1:50m。首都高程另取细网格。']);
            case 'centrifugal'
                sourceLabel.Text=sprintf(['离心量：a_c = ω²(ν+h)cosφ，h = ETOPO高程 + 大地水准面高N；地表/海底Δh=0，结果已缓存。\n' ...
                    '高程来源：NOAA ETOPO 2022；WGS84自转常数。个人相对高程仅影响右侧计算器；g已经包含离心项。']);
            otherwise
                sourceLabel.Text=sprintf(['重力：ICGEM / NGA EGM2008，180阶，1°网格，WGS84椭球面h=0；右侧按当地地表及相对高程计算。\n' ...
                    '来源：icgem.gfz-potsdam.de；高程：NOAA ETOPO 2022；国界：Natural Earth 1:50m。重力模式凹凸不是地形。']);
        end
    end
    function scene=createScene(index,D)
        a=axesList(index); p=projections{index}; hold(a,'on');
        a.FontSize=11; a.Color=[0.98 0.99 1];
        scene=struct('axes',a,'projection',p,'key','', ...
            'relief',NaN,'opacity',NaN,'fitRadius',1+radialAmplitude()+0.035);
        if strcmp(p,'globe')
            % Native zoom narrows XYZ limits; clip at the screen rectangle
            % instead of cutting away the front of the sphere at those limits.
            a.ClippingStyle='rectangle';
            scene.core=surf(a,zeros(2),zeros(2),zeros(2), ...
                'FaceColor',[0.78 0.82 0.86],'EdgeColor','none', ...
                'HitTest','off','PickableParts','none','Tag','OpaqueCore');
            scene.field=surf(a,zeros(2),zeros(2),zeros(2),zeros(2), ...
                'EdgeColor','none','FaceColor','interp', ...
                'HitTest','off','PickableParts','none','Tag','GravitySurface');
            scene.contours=plot3(a,NaN,NaN,NaN,'Color',[0.42 0.49 0.52], ...
                'LineWidth',0.3,'HitTest','off','PickableParts','none','Tag','GravityContours');
            scene.halo=plot3(a,NaN,NaN,NaN,'Color',[1 1 1],'LineWidth',2.2, ...
                'HitTest','off','PickableParts','none','Tag','BoundaryHalo');
            scene.boundaries=plot3(a,NaN,NaN,NaN,'Color',[0.05 0.07 0.1],'LineWidth',1.0, ...
                'HitTest','off','PickableParts','none','Tag','CountryBoundaries');
            scene.capitals=scatter3(a,NaN,NaN,NaN,20,[0.95 0.05 0.09],'filled', ...
                'MarkerEdgeColor',[0.4 0 0],'LineWidth',0.3, ...
                'ButtonDownFcn',@pickCapital,'Tag','CapitalMarkers');
            scene.highlight=plot3(a,NaN,NaN,NaN,'o','MarkerSize',12, ...
                'MarkerEdgeColor',[0.05 0.05 0.05],'LineWidth',2, ...
                'HitTest','off','Tag','SelectedCapital');
            axis(a,'equal','off'); fitCamera(a,scene.fitRadius);
            a.Interactions=[rotateInteraction zoomInteraction];
        else
            valid=true(size(D.lat));
            if strcmp(p,'mercator'), valid=abs(D.lat)<=85; end
            [x,y]=gravity_project(D.longrid(valid,:),D.latgrid(valid,:),p);
            [~,scene.field]=contourf(a,x,y,D.values(valid,:),D.levels, ...
                'LineColor','none','Tag','GravityContours');
            scene.halo=plot(a,NaN,NaN,'Color',[1 1 1],'LineWidth',1.6, ...
                'HitTest','off','PickableParts','none','Tag','BoundaryHalo');
            scene.boundaries=plot(a,NaN,NaN,'Color',[0.07 0.08 0.1],'LineWidth',0.6, ...
                'HitTest','off','PickableParts','none','Tag','CountryBoundaries');
            scene.capitals=scatter(a,NaN,NaN,18,[0.95 0.05 0.09],'filled', ...
                'MarkerEdgeColor',[0.4 0 0],'LineWidth',0.3, ...
                'ButtonDownFcn',@pickCapital,'Tag','CapitalMarkers');
            scene.highlight=plot(a,NaN,NaN,'o','MarkerSize',12, ...
                'MarkerEdgeColor',[0.05 0.05 0.05],'LineWidth',2, ...
                'HitTest','off','Tag','SelectedCapital');
            axis(a,'equal'); box(a,'on'); a.XTick=[]; a.YTick=[];
            if strcmp(p,'mercator')
                xlabel(a,'Mercator：纬度限制在 ±85°，两极不在图内');
            else
                xlabel(a,'红点：197 国首都；线：国界；色带：所选物理量等值分级');
            end
            a.Interactions=[panInteraction zoomInteraction];
        end
        scene.colorbar=colorbar(a); scene.colorbar.FontSize=10;
        hold(a,'off');
    end
    function scene=updateGeometry(scene,D)
        a=scene.axes; p=scene.projection;
        if strcmp(p,'globe')
            amplitude=radialAmplitude();
            r=1+amplitude*D.normalized;
            set(scene.field,'XData',D.gx.*r,'YData',D.gy.*r,'ZData',D.gz.*r,'CData',D.values);
            if strcmp(D.quality,'fast')
                set(scene.core,'XData',zeros(2),'YData',zeros(2),'ZData',zeros(2),'Visible','off');
            else
                set(scene.core,'XData',D.gx.*(r-0.003),'YData',D.gy.*(r-0.003),'ZData',D.gz.*(r-0.003));
            end
            r=1+amplitude*D.bn+0.009;
            set(scene.boundaries,'XData',D.bx.*r,'YData',D.by.*r,'ZData',D.bz.*r);
            set(scene.halo,'XData',D.bx.*r,'YData',D.by.*r,'ZData',D.bz.*r);
            r=1+amplitude*D.tn+0.004;
            set(scene.contours,'XData',D.tx.*r,'YData',D.ty.*r,'ZData',D.tz.*r);
            r=1+amplitude*D.cn+0.016;
            x=D.cx.*r; y=D.cy.*r; z=D.cz.*r;
            set(scene.capitals,'XData',x,'YData',y,'ZData',z);
            scene.capitalXYZ=[x(:) y(:) z(:)];
            rlim=1+amplitude+0.035;
            if rlim~=scene.fitRadius
                % Native zoom changes limits. Scale the current limits so
                % relief updates preserve that zoom, then keep the same
                % automatic camera model used by native rotation.
                scale=rlim/scene.fitRadius;
                a.XLim=a.XLim*scale; a.YLim=a.YLim*scale; a.ZLim=a.ZLim*scale;
                a.CameraTargetMode='auto'; a.CameraPositionMode='auto';
                scene.fitRadius=rlim;
            end
        else
            valid=true(size(D.lat));
            if strcmp(p,'mercator'), valid=abs(D.lat)<=85; end
            [x,y]=gravity_project(D.longrid(valid,:),D.latgrid(valid,:),p);
            set(scene.field,'XData',x,'YData',y,'ZData',D.values(valid,:),'LevelList',D.levels);
            [x,y]=gravity_project(D.boundaryLon,D.boundaryLat,p);
            if strcmp(p,'mercator'), x(abs(D.boundaryLat)>85)=NaN; y(abs(D.boundaryLat)>85)=NaN; end
            set(scene.boundaries,'XData',x,'YData',y);
            set(scene.halo,'XData',x,'YData',y);
            [x,y]=gravity_project(capitalLon,capitalLat,p);
            set(scene.capitals,'XData',x,'YData',y);
            scene.capitalXYZ=[x(:) y(:) zeros(numel(x),1)];
            % Fit only the first build; a user's map zoom survives updates.
            if isempty(scene.key), axis(a,'tight'); end
        end
    end
    function fitCamera(a,rlim)
        a.Projection='orthographic'; a.DataAspectRatio=[1 1 1]; a.PlotBoxAspectRatio=[1 1 1];
        xlim(a,[-rlim rlim]); ylim(a,[-rlim rlim]); zlim(a,[-rlim rlim]);
        % Native rotation writes View and restores the automatic camera
        % distance. Fit with that same distance so the first drag cannot
        % silently zoom out. Change the view angle to retain the large globe.
        view(a,currentView);
        a.CameraTarget=[0 0 0];
        a.CameraPositionMode='auto';
        distance=norm(a.CameraPosition-a.CameraTarget);
        a.CameraUpVector=[0 0 1];
        a.CameraViewAngle=2*atand(rlim/distance);
        axis(a,'vis3d');
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
