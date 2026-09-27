function tests = test_viewport_colors
%TEST_VIEWPORT_COLORS Automatic visible-range colors for 2-D centrifugal maps.
% Uses the real bundled field and native axes limit listeners. MATLAB runs
% these tests after the main app's LocalColorScale interface is available.
tests=functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.TestData.originalPath=path;
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root);
testCase.TestData.figure=gravity_field_app('Visible','off','RenderQuality','fine');
testCase.TestData.environment=load_surface_environment();
testCase.TestData.gravity=load(fullfile(root,'data','gravity_grid.mat'));
localScale=control(testCase.TestData.figure,'LocalColorScale');
assertTrue(testCase,logical(localScale.Value),'Local colors should be enabled by default.');
settle();
end

function setup(testCase)
fig=testCase.TestData.figure;
setControl(fig,'RenderQuality','fine');
setControl(fig,'FieldMode','centrifugal');
setControl(fig,'CentrifugalUnit','acceleration');
setControl(fig,'Mass',70);
setControl(fig,'Altitude',0);
setControl(fig,'LocalColorScale',true);
showTab(fig,'miller');
fullView(plotAxes(fig,'miller'));
end

function teardownOnce(testCase)
if isfield(testCase.TestData,'figure') && isgraphics(testCase.TestData.figure)
    delete(testCase.TestData.figure);
end
if isfield(testCase.TestData,'originalPath')
    path(testCase.TestData.originalPath);
end
end

function testViewportLimitsAcrossFourProjectionsAndBothUnits(testCase)
fig=testCase.TestData.figure;
for unit={'acceleration','force'}
    setControl(fig,'CentrifugalUnit',unit{1});
    expectedGlobal=centrifugalGlobal(testCase,unit{1},70);
    for projection={'miller','equirectangular','mercator','mollweide'}
        name=projection{1}; showTab(fig,name); a=plotAxes(fig,name);
        fullView(a);
        verifyViewport(testCase,a,'global');
        verifyEqual(testCase,a.CLim,expectedGlobal,'AbsTol',2e-12);
        field=mapField(a); sourceValues=field.ZData;
        [xl,yl]=geographicWindow(name,[70 110],[20 40]);
        setView(a,xl,yl);
        stats=verifyViewport(testCase,a,'local');
        [~,visible]=visibleNodes(a);
        assertGreaterThan(testCase,numel(visible),10);
        verifyEncloses(testCase,a.CLim,visible);
        verifyGreaterThan(testCase,stats.sampleCount,0);
        verifyLessThan(testCase,diff(a.CLim),0.5*diff(expectedGlobal));
        verifyEqual(testCase,field.ZData,sourceValues);
        markers=findobj(a,'Tag','CapitalMarkers');
        verifyNumElements(testCase,markers.XData,197);
        fullView(a);
        verifyViewport(testCase,a,'global');
        verifyEqual(testCase,a.CLim,expectedGlobal,'AbsTol',2e-12);
    end
end
end

function testCheckboxAndOtherFieldsRestoreGlobalScale(testCase)
fig=testCase.TestData.figure;
mode=control(fig,'FieldMode');
verifyEqual(testCase,sort(string(mode.ItemsData)), ...
    sort(["disturbance","gravity","elevation","centrifugal"]));
showTab(fig,'miller'); a=plotAxes(fig,'miller');
[xl,yl]=geographicWindow('miller',[70 110],[20 40]);
setView(a,xl,yl); verifyViewport(testCase,a,'local');
setControl(fig,'LocalColorScale',false);
verifyViewport(testCase,a,'global');
verifyEqual(testCase,a.CLim,centrifugalGlobal(testCase,'acceleration',70),'AbsTol',2e-12);
setView(a,xl+0.1,yl+0.05);
verifyViewport(testCase,a,'global');
verifyEqual(testCase,a.CLim,centrifugalGlobal(testCase,'acceleration',70),'AbsTol',2e-12);
setControl(fig,'LocalColorScale',true);
verifyViewport(testCase,a,'local');
for name={'gravity','disturbance','elevation'}
    setControl(fig,'FieldMode',name{1});
    switch name{1}
        case 'gravity', values=double(testCase.TestData.gravity.g);
        case 'disturbance', values=double(testCase.TestData.gravity.disturbance)*1e5;
        case 'elevation', values=double(testCase.TestData.environment.elevationM);
    end
    verifyViewport(testCase,a,'global');
    verifyEqual(testCase,a.CLim,[min(values(:)),max(values(:))],'AbsTol',2e-9);
    setView(a,xl,yl);
    verifyViewport(testCase,a,'global');
    verifyEqual(testCase,a.CLim,[min(values(:)),max(values(:))],'AbsTol',2e-9);
end
% The switch is scoped to 2-D views; a globe retains the global range.
setControl(fig,'FieldMode','centrifugal'); showTab(fig,'globe');
globe=plotAxes(fig,'globe');
verifyEqual(testCase,globe.CLim,centrifugalGlobal(testCase,'acceleration',70),'AbsTol',2e-12);
end

function testMassScalingAndZeroMassStayFinite(testCase)
fig=testCase.TestData.figure;
setControl(fig,'CentrifugalUnit','force');
for projection={'miller','equirectangular','mercator','mollweide'}
    name=projection{1}; showTab(fig,name); a=plotAxes(fig,name);
    setControl(fig,'Mass',40); setControl(fig,'Altitude',0);
    [xl,yl]=geographicWindow(name,[70 110],[20 40]);
    setView(a,xl,yl);
    verifyViewport(testCase,a,'local');
    limits40=a.CLim; field=mapField(a); values40=field.ZData;
    setControl(fig,'Mass',80);
    verifyViewport(testCase,a,'local');
    verifyEqual(testCase,a.CLim,2*limits40,'AbsTol',2e-11);
    verifyEqual(testCase,field.ZData,2*values40,'AbsTol',2e-11);
    limits80=a.CLim; values80=field.ZData;
    setControl(fig,'Altitude',2000);
    verifyEqual(testCase,a.CLim,limits80,'AbsTol',2e-11);
    verifyEqual(testCase,field.ZData,values80);
    setControl(fig,'Mass',0);
    verifyTrue(testCase,all(isfinite(a.CLim)) && a.CLim(1)<a.CLim(2));
    verifyLessThanOrEqual(testCase,a.CLim(1),0);
    verifyGreaterThanOrEqual(testCase,a.CLim(2),0);
    verifyEqual(testCase,field.ZData,zeros(size(field.ZData)),'AbsTol',1e-14);
    verifyLevels(testCase,a);
    stats=viewportStats(testCase,a);
    verifyTrue(testCase,any(strcmp(stats.mode,{'local','global'})));
    verifyGreaterThan(testCase,stats.sampleCount,0);
end
end

function testEmptyViewportPreservesLastValidRange(testCase)
fig=testCase.TestData.figure;
showTab(fig,'mollweide'); a=plotAxes(fig,'mollweide');
for unit={'acceleration','force'}
    setControl(fig,'CentrifugalUnit',unit{1});
    [xl,yl]=geographicWindow('mollweide',[70 110],[20 40]);
    setView(a,xl,yl); verifyViewport(testCase,a,'local');
    validLimits=a.CLim; field=mapField(a); validLevels=field.LevelList;
    [x,y]=fieldCoordinates(field);
    % Outside the map, so neither grid nodes nor boundary intersections exist.
    setView(a,max(x(:))+[5 6],max(y(:))+[5 6]);
    stats=verifyViewport(testCase,a,'empty');
    verifyEqual(testCase,stats.sampleCount,0);
    verifyEqual(testCase,a.CLim,validLimits,'AbsTol',2e-12);
    verifyEqual(testCase,field.LevelList,validLevels,'AbsTol',2e-12);
    setView(a,xl,yl); verifyViewport(testCase,a,'local');
    verifyEqual(testCase,a.CLim,validLimits,'AbsTol',2e-12);
    fullView(a); verifyViewport(testCase,a,'global');
end
end

function testNarrowLatitudeShowsTerrainAndSubcellZoomWorks(testCase)
fig=testCase.TestData.figure;
showTab(fig,'equirectangular'); a=plotAxes(fig,'equirectangular');
field=mapField(a); environment=testCase.TestData.environment;
latitude=30; longitudeRange=[65 110];
[xl,yl]=geographicWindow('equirectangular',longitudeRange,latitude+[-1 1]*1e-5);
setView(a,xl,yl);
verifyViewport(testCase,a,'local');
[mask,values]=visibleNodes(a); [~,y]=fieldCoordinates(field);
assertGreaterThan(testCase,numel(values),20);
verifyNumElements(testCase,unique(y(mask)),1);
row=find(double(environment.lat(:))==latitude,1);
cols=double(environment.lon(:)')>=longitudeRange(1) & ...
    double(environment.lon(:)')<=longitudeRange(2);
heights=double(environment.hSurface(row,cols));
expectedRange=(7.292115e-5)^2*cosd(latitude)*(max(heights)-min(heights));
% At a fixed latitude, this variation can only come from ellipsoidal height.
verifyGreaterThan(testCase,expectedRange,1e-7);
verifyEqual(testCase,max(values)-min(values),expectedRange,'AbsTol',2e-13);
verifyEncloses(testCase,a.CLim,values);
verifyLessThan(testCase,diff(a.CLim),1.15*expectedRange);
verifyLessThan(testCase,diff(a.CLim),0.01*diff(centrifugalGlobal(testCase,'acceleration',70)));
% A viewport wholly inside a source cell has no node centers. Interpolated
% edge/corner samples must still produce a finite, useful local scale.
[xl,yl]=geographicWindow('equirectangular',[90.2 90.4],[30.25 30.27]);
setView(a,xl,yl);
stats=verifyViewport(testCase,a,'local');
[~,visible]=visibleNodes(a); verifyEmpty(testCase,visible);
[x,y]=fieldCoordinates(field);
corners=interp2(x,y,double(field.ZData),[xl(1) xl(2) xl(1) xl(2)], ...
    [yl(1) yl(1) yl(2) yl(2)],'linear');
verifyGreaterThan(testCase,stats.sampleCount,0);
verifyTrue(testCase,all(isfinite(corners)));
verifyEncloses(testCase,a.CLim,corners);
verifyLessThan(testCase,diff(a.CLim),0.01*diff(centrifugalGlobal(testCase,'acceleration',70)));
end

function testViewportChangesLeaveDataAndEnvironmentCacheUnchanged(testCase)
fig=testCase.TestData.figure;
cacheBefore=getappdata(fig,'EnvironmentCache');
diskBefore=cacheSnapshot(cacheBefore.cacheFile);
calculatorBefore=fig.UserData;
for projection={'miller','equirectangular','mercator','mollweide'}
    name=projection{1}; showTab(fig,name); a=plotAxes(fig,name);
    field=mapField(a); originalValues=field.ZData;
    for origin=[20 30;70 -20;-100 45]'
        [xl,yl]=geographicWindow(name,origin(1)+[0 20],origin(2)+[0 8]);
        setView(a,xl,yl); verifyViewport(testCase,a,'local');
        verifyEqual(testCase,field.ZData,originalValues);
        verifyEqual(testCase,fig.UserData,calculatorBefore);
    end
    fullView(a);
    verifyEqual(testCase,field.ZData,originalValues);
end
verifyEqual(testCase,getappdata(fig,'EnvironmentCache'),cacheBefore);
verifyEqual(testCase,cacheSnapshot(cacheBefore.cacheFile),diskBefore);
end

function testDeletingFigureCancelsPendingViewportTimer(testCase)
% Own a separate figure so the suite's shared TestData figure stays alive.
tag='GravityViewportTimer';
beforeCount=numel(timerfindall('Tag',tag));
sharedFigure=testCase.TestData.figure;
sharedState=sharedFigure.UserData;
probe=gravity_field_app('Visible','off','RenderQuality','fast');
finish=onCleanup(@()deleteFigureIfValid(probe)); %#ok<NASGU>
setControl(probe,'FieldMode','centrifugal');
setControl(probe,'CentrifugalUnit','acceleration');
setControl(probe,'LocalColorScale',true);
showTab(probe,'miller');
a=plotAxes(probe,'miller');
withProbeCount=numel(timerfindall('Tag',tag));
[xl,yl]=geographicWindow('miller',[70 110],[20 40]);
% Deliberately do not drawnow/pause here: delete during the debounce delay.
set(a,'XLim',xl,'YLim',yl);
wasPending=~isempty(timerfindall('Tag',tag,'Running','on'));
delete(probe);
verifyEqual(testCase,withProbeCount,beforeCount+1);
verifyTrue(testCase,wasPending,'The limits change should queue a viewport timer.');
verifyEqual(testCase,numel(timerfindall('Tag',tag)),beforeCount);
settle();
verifyEqual(testCase,numel(timerfindall('Tag',tag)),beforeCount);
verifyTrue(testCase,isgraphics(sharedFigure));
verifyEqual(testCase,sharedFigure.UserData,sharedState);
end

function limits=centrifugalGlobal(testCase,unit,mass)
values=double(testCase.TestData.environment.acSurface);
if strcmp(unit,'force'), values=values*mass; end
limits=[min(values(:)),max(values(:))];
end

function stats=verifyViewport(testCase,a,expectedMode)
stats=viewportStats(testCase,a);
verifyEqual(testCase,char(stats.mode),expectedMode);
verifyEqual(testCase,double(stats.limits(:)'),a.CLim,'AbsTol',2e-12);
verifyTrue(testCase,all(isfinite(a.CLim)) && a.CLim(1)<a.CLim(2));
verifyLevels(testCase,a);
end

function stats=viewportStats(testCase,a)
stats=getappdata(a,'ViewportColorStats');
assertTrue(testCase,isstruct(stats) && isscalar(stats));
assertTrue(testCase,all(isfield(stats,{'mode','limits','sampleCount'})));
verifyTrue(testCase,isfinite(stats.sampleCount) && stats.sampleCount>=0);
end

function verifyLevels(testCase,a)
field=mapField(a); levels=double(field.LevelList(:)');
assertGreaterThan(testCase,numel(levels),1);
verifyTrue(testCase,all(isfinite(levels)) && all(diff(levels)>0));
% Nineteen local levels include both CLim endpoints. Up to two outside
% levels retain the global extrema, preventing unfilled low-value regions.
expected=linspace(a.CLim(1),a.CLim(2),19);
nearest=zeros(size(expected));
for k=1:numel(expected), nearest(k)=min(abs(levels-expected(k))); end
verifyLessThanOrEqual(testCase,nearest,2e-12);
verifyGreaterThanOrEqual(testCase,numel(levels),19);
verifyLessThanOrEqual(testCase,numel(levels),21);
values=double(field.ZData);
verifyLessThanOrEqual(testCase,levels(1),min(values(:))+2e-12);
verifyGreaterThanOrEqual(testCase,levels(end),max(values(:))-2e-12);
stats=viewportStats(testCase,a);
if strcmp(stats.mode,'global')
    verifyNumElements(testCase,levels,19);
    verifyEqual(testCase,levels,expected,'AbsTol',2e-12);
end
end

function verifyEncloses(testCase,limits,values)
tolerance=max(1e-12,1e-10*max(abs(values(:))));
verifyLessThanOrEqual(testCase,limits(1),min(values(:))+tolerance);
verifyGreaterThanOrEqual(testCase,limits(2),max(values(:))-tolerance);
end

function [mask,values]=visibleNodes(a)
field=mapField(a); [x,y]=fieldCoordinates(field); z=double(field.ZData);
mask=isfinite(z) & isfinite(x) & isfinite(y) & ...
    x>=a.XLim(1) & x<=a.XLim(2) & y>=a.YLim(1) & y<=a.YLim(2);
values=z(mask);
end

function [x,y]=fieldCoordinates(field)
x=double(field.XData); y=double(field.YData);
if isvector(x) && isvector(y) && ~isequal(size(x),size(field.ZData))
    [x,y]=meshgrid(x,y);
end
end

function [xl,yl]=geographicWindow(projection,lonBounds,latBounds)
[lon,lat]=meshgrid(linspace(lonBounds(1),lonBounds(2),21), ...
    linspace(latBounds(1),latBounds(2),21));
[x,y]=gravity_project(lon,lat,projection);
xl=[min(x(:)) max(x(:))]; yl=[min(y(:)) max(y(:))];
end

function fullView(a)
[x,y]=fieldCoordinates(mapField(a));
xl=[min(x(:)) max(x(:))]; yl=[min(y(:)) max(y(:))];
setView(a,xl+[-1 1]*0.02*diff(xl),yl+[-1 1]*0.02*diff(yl));
end

function setView(a,xLimits,yLimits)
set(a,'XLim',xLimits,'YLim',yLimits);
settle();
end

function snapshot=cacheSnapshot(path)
listing=dir(path);
if numel(listing)~=1, error('ViewportColorTest:Cache','Expected a persisted environment cache.'); end
saved=load(path,'record');
snapshot=struct('bytes',listing.bytes,'modified',listing.datenum, ...
    'identity',saved.record.identity,'payloadSHA256',saved.record.payloadSHA256, ...
    'createdUTC',saved.record.createdUTC);
end

function field=mapField(a)
field=findobj(a,'Tag','GravityContours');
if numel(field)~=1, error('ViewportColorTest:Field','Expected one 2-D contour field.'); end
end

function setControl(fig,tag,value)
item=control(fig,tag);
if ~isequal(item.Value,value)
    item.Value=value;
    callback=item.ValueChangedFcn; callback(item,[]);
    settle();
end
end

function item=control(fig,tag)
item=findobj(fig,'Tag',tag);
if numel(item)~=1, error('ViewportColorTest:Control','Expected one control with Tag=%s.',tag); end
end

function showTab(fig,name)
tabs=control(fig,'ProjectionTabs'); tabs.SelectedTab=control(fig,name);
callback=tabs.SelectionChangedFcn; callback(tabs,[]);
settle();
end

function a=plotAxes(fig,name)
a=findobj(control(fig,name),'Type','axes');
end

function settle()
drawnow;
pause(0.25); % Allow the 150 ms limits debounce timer to fire.
drawnow;
end

function deleteFigureIfValid(fig)
if isgraphics(fig), delete(fig); end
end
