function tests = test_environment_ui
%TEST_ENVIRONMENT_UI Measured surface heights and centrifugal UI integration.
% Requires the real bundled terrain_data.mat; no synthetic UI fixture is
% generated. Run this file after terrain generation with the main UI suite.
tests=functiontests(localfunctions);
end

function setupOnce(testCase)
root=fileparts(fileparts(mfilename('fullpath')));
testCase.TestData.originalPath=path;
addpath(root);
testCase.TestData.root=root;
testCase.TestData.figure=gravity_field_app('Visible','off','RenderQuality','balanced');
testCase.TestData.environment=load_surface_environment();
testCase.TestData.gravityGrid=load(fullfile(root,'data','gravity_grid.mat'),'g');
drawnow;
end

function setup(testCase)
fig=testCase.TestData.figure;
setControl(fig,'FieldMode','disturbance');
setControl(fig,'CentrifugalUnit','acceleration');
setControl(fig,'RenderQuality','balanced');
setControl(fig,'Relief',0.16);
setControl(fig,'Opacity',0.78);
setControl(fig,'Mass',70);
setControl(fig,'Altitude',0);
selectCountry(fig,'CHN');
showTab(fig,'globe');
end

function teardownOnce(testCase)
if isfield(testCase.TestData,'figure') && isgraphics(testCase.TestData.figure)
    delete(testCase.TestData.figure);
end
if isfield(testCase.TestData,'originalPath')
    path(testCase.TestData.originalPath);
end
end

function testHeightCompositionAndIndependentPhysics(testCase)
fig=testCase.TestData.figure;
environment=testCase.TestData.environment;
altitudeLabel=control(fig,'AltitudeLabel');
verifyTrue(testCase,contains(string(altitudeLabel.Text),'相对高程'));
% Include northern, near-equatorial and southern capitals with actual H_s,N.
for code={'CHN','ECU','AUS'}
    selectCountry(fig,code{1});
    source=find(strcmp(cellstr(environment.capitalIso3),code{1}),1);
    assertNotEmpty(testCase,source);
    for relativeHeight=[0 1200]
        setControl(fig,'Altitude',relativeHeight);
        s=fig.UserData;
        Hs=environment.capitalElevationM(source);
        N=environment.capitalGeoidM(source);
        h=Hs+relativeHeight+N;
        verifyEqual(testCase,s.surfaceElevation,Hs,'AbsTol',1e-9);
        verifyEqual(testCase,s.geoidUndulation,N,'AbsTol',1e-9);
        verifyEqual(testCase,s.relativeHeight,relativeHeight);
        verifyEqual(testCase,s.height,relativeHeight);
        verifyEqual(testCase,s.altitude,Hs+relativeHeight,'AbsTol',1e-9);
        verifyEqual(testCase,s.ellipsoidalHeight,h,'AbsTol',1e-9);
        % EGM2008's effective g already includes centrifugal acceleration.
        % Direct agreement rejects any second addition/subtraction of F_c.
        expectedG=gravity_at_location(s.latitude,s.longitude,h);
        expectedAc=independentCentrifugal(s.latitude,h);
        verifyEqual(testCase,s.g,expectedG,'AbsTol',2e-10);
        verifyEqual(testCase,s.force,s.mass*expectedG,'AbsTol',2e-8);
        verifyEqual(testCase,s.centrifugalAcceleration,expectedAc,'AbsTol',2e-13);
        verifyEqual(testCase,s.centrifugalForce,s.mass*expectedAc,'AbsTol',2e-11);
        calculation=control(fig,'Calculation');
        text=join(string(calculation.Value),newline);
        for token={'H_s =','N =','H =','h =','a_c =','F_c ='}
            verifyTrue(testCase,contains(text,token{1}));
        end
        coordinatesLabel=control(fig,'Coordinates');
        coordinates=string(coordinatesLabel.Text);
        verifyTrue(testCase,contains(coordinates,sprintf('%.1f',Hs)));
        forceLabel=control(fig,'CentrifugalForce');
        forceText=string(forceLabel.Text);
        verifyTrue(testCase,contains(forceText,sprintf('%.6f',s.centrifugalForce)));
        verifyTrue(testCase,contains(forceText,'N'));
    end
end
end

function testGlobalSurfaceFieldsUseMeasuredElevations(testCase)
fig=testCase.TestData.figure;
environment=testCase.TestData.environment;
setControl(fig,'RenderQuality','fine');
setControl(fig,'FieldMode','elevation');
a=plotAxes(fig,'globe');
values=fieldValues(a,'globe');
verifyEqual(testCase,values,double(environment.elevationM),'AbsTol',1e-9);
% The full ETOPO grid must retain ocean seabed values below sea level.
verifyLessThan(testCase,min(values(:)),-1000);
verifyGreaterThan(testCase,max(values(:)),1000);
setControl(fig,'FieldMode','centrifugal');
unit=control(fig,'CentrifugalUnit');
verifyEqual(testCase,unit.Value,'acceleration');
values=fieldValues(a,'globe');
latitudes=repmat(double(environment.lat(:)),1,numel(environment.lon));
expected=independentCentrifugal(latitudes, ...
    double(environment.hSurface));
verifyEqual(testCase,values,expected,'AbsTol',2e-13);
verifyEqual(testCase,values,double(environment.acSurface),'AbsTol',2e-13);
verifyGreaterThanOrEqual(testCase,min(values(:)),0);
verifyLessThan(testCase,max(values(:)),0.035);
end

function testCoastalCapitalEstimatesAreDisclosed(testCase)
fig=testCase.TestData.figure;
environment=testCase.TestData.environment;
codes=cellstr(environment.capitalIso3);
approved={'BHS','COK','MDV','MHL','NRU'};
verifyEqual(testCase,sum(environment.capitalElevationIsEstimate(:)),5);
for k=1:numel(approved)
    code=approved{k}; selectCountry(fig,code);
    i=find(strcmp(codes,code),1);
    verifyTrue(testCase,logical(environment.capitalElevationIsEstimate(i)));
    verifyLessThan(testCase,environment.capitalRawElevationM(i),0);
    verifyGreaterThan(testCase,environment.capitalElevationM(i),0);
    distance=environment.capitalElevationSampleDistanceM(i);
    verifyGreaterThan(testCase,distance,0);
    verifyLessThanOrEqual(testCase,distance,1500);
    verifyTrue(testCase,fig.UserData.elevationNearbyEstimate);
    verifyEqual(testCase,fig.UserData.elevationSampleDistance,distance);
    verifyEqual(testCase,fig.UserData.latitude,environment.capitalLatitude(i));
    verifyEqual(testCase,fig.UserData.longitude,environment.capitalLongitude(i));
    coordinates=control(fig,'Coordinates');
    calculation=control(fig,'Calculation');
    for displayed={string(coordinates.Text),join(string(calculation.Value),newline)}
        verifyTrue(testCase,contains(displayed{1},'邻近陆地估计'));
        verifyTrue(testCase,contains(displayed{1},sprintf('%.0f m',distance)));
    end
end
end

function testPersonalParametersAndForceMapRespectCache(testCase)
fig=testCase.TestData.figure;
cacheBefore=getappdata(fig,'EnvironmentCache');
assertTrue(testCase,isstruct(cacheBefore) && isfield(cacheBefore,'cacheFile'));
diskBefore=cacheSnapshot(cacheBefore.cacheFile);
setControl(fig,'RenderQuality','fine');
for field={'disturbance','gravity','elevation','centrifugal'}
    setControl(fig,'FieldMode',field{1});
    setControl(fig,'CentrifugalUnit','acceleration');
    setControl(fig,'Mass',60); setControl(fig,'Altitude',0);
    a=plotAxes(fig,'globe'); valuesBefore=fieldValues(a,'globe');
    s0=fig.UserData;
    setControl(fig,'Mass',120);
    verifyEqual(testCase,fig.UserData.g,s0.g,'AbsTol',1e-13);
    verifyEqual(testCase,fig.UserData.force,2*s0.force,'AbsTol',2e-8);
    verifyEqual(testCase,fieldValues(a,'globe'),valuesBefore);
    setControl(fig,'Altitude',1000);
    verifyLessThan(testCase,fig.UserData.g,s0.g);
    verifyGreaterThan(testCase,fig.UserData.centrifugalAcceleration,s0.centrifugalAcceleration);
    verifyEqual(testCase,fieldValues(a,'globe'),valuesBefore);
end
% Only force-in-newtons maps scale their global values with the user's mass.
setControl(fig,'Altitude',0); setControl(fig,'Mass',50);
setControl(fig,'FieldMode','centrifugal');
setControl(fig,'CentrifugalUnit','force');
a=plotAxes(fig,'globe'); values50=fieldValues(a,'globe');
verifyEqual(testCase,values50,50*double(testCase.TestData.environment.acSurface),'AbsTol',2e-11);
force50=fig.UserData.centrifugalForce;
setControl(fig,'Mass',100);
verifyEqual(testCase,fieldValues(a,'globe'),2*values50,'AbsTol',2e-11);
verifyEqual(testCase,fig.UserData.centrifugalForce,2*force50,'AbsTol',2e-11);
values100=fieldValues(a,'globe');
setControl(fig,'Altitude',2500);
verifyEqual(testCase,fieldValues(a,'globe'),values100);
verifyGreaterThan(testCase,fig.UserData.centrifugalForce,2*force50);
verifyEqual(testCase,getappdata(fig,'EnvironmentCache'),cacheBefore);
verifyEqual(testCase,cacheSnapshot(cacheBefore.cacheFile),diskBefore);
end

function testNewFieldsAllQualitiesAndProjections(testCase)
fig=testCase.TestData.figure;
setControl(fig,'Altitude',350);
baseline=fig.UserData;
for field={'elevation','centrifugal'}
    setControl(fig,'FieldMode',field{1});
    for quality={'fast','balanced','fine'}
        setControl(fig,'RenderQuality',quality{1});
        for projection={'globe','miller','equirectangular','mercator','mollweide'}
            showTab(fig,projection{1}); a=plotAxes(fig,projection{1});
            verifyCapitalMarkers(testCase,a);
            values=fieldValues(a,projection{1});
            verifyTrue(testCase,isreal(values) && all(isfinite(values(:))));
            verifyEqual(testCase,fig.UserData.g,baseline.g,'AbsTol',1e-13);
            verifyEqual(testCase,fig.UserData.force,baseline.force,'AbsTol',2e-8);
            verifyEqual(testCase,fig.UserData.ellipsoidalHeight,baseline.ellipsoidalHeight);
            stats=getappdata(fig,'RenderStats');
            verifyEqual(testCase,stats.quality,quality{1});
            verifyEqual(testCase,stats.projection,projection{1});
        end
    end
end
showTab(fig,'globe'); setControl(fig,'RenderQuality','fine');
setControl(fig,'FieldMode','gravity');
verifyEqual(testCase,fieldValues(plotAxes(fig,'globe'),'globe'), ...
    double(testCase.TestData.gravityGrid.g),'AbsTol',2e-10);
verifyEqual(testCase,fig.UserData.g,baseline.g,'AbsTol',1e-13);
end

function testZeroMassForceMapIsFiniteEverywhere(testCase)
fig=testCase.TestData.figure;
setControl(fig,'FieldMode','centrifugal');
setControl(fig,'CentrifugalUnit','force');
setControl(fig,'Mass',0);
verifyEqual(testCase,fig.UserData.force,0);
verifyEqual(testCase,fig.UserData.centrifugalForce,0);
verifyGreaterThan(testCase,fig.UserData.g,9.7);
verifyGreaterThan(testCase,fig.UserData.centrifugalAcceleration,0);
for quality={'fast','balanced','fine'}
    setControl(fig,'RenderQuality',quality{1});
    for projection={'globe','miller','equirectangular','mercator','mollweide'}
        showTab(fig,projection{1}); a=plotAxes(fig,projection{1});
        verifyCapitalMarkers(testCase,a);
        values=fieldValues(a,projection{1});
        verifyEqual(testCase,values,zeros(size(values)),'AbsTol',1e-14);
        verifyTrue(testCase,all(isfinite(a.CLim)) && a.CLim(1)<a.CLim(2));
        if strcmp(projection{1},'globe')
            surface=findobj(a,'Tag','GravitySurface');
            radius=sqrt(surface.XData.^2+surface.YData.^2+surface.ZData.^2);
            verifyTrue(testCase,all(isfinite(radius(:))));
            verifyEqual(testCase,radius,ones(size(radius)),'AbsTol',1e-12);
        end
    end
end
end

function testEnvironmentGlobeRotationRetainsScale(testCase)
fig=testCase.TestData.figure;
showTab(fig,'globe'); a=plotAxes(fig,'globe');
for field={'elevation','centrifugal'}
    setControl(fig,'FieldMode',field{1});
    for quality={'fast','balanced','fine'}
        setControl(fig,'RenderQuality',quality{1});
        surface=findobj(a,'Tag','GravitySurface');
        originalXYZ={surface.XData,surface.YData,surface.ZData};
        originalSpan=cameraSpan(a); originalView=a.View;
        for offset=[30 10;-95 -20;150 35]'
            a.View=originalView+offset'; drawnow;
            verifyEqual(testCase,cameraSpan(a),originalSpan,'RelTol',1e-10);
            verifyEqual(testCase,{surface.XData,surface.YData,surface.ZData},originalXYZ);
        end
        showTab(fig,'miller'); showTab(fig,'globe');
        verifyEqual(testCase,cameraSpan(a),originalSpan,'RelTol',1e-10);
        verifyEqual(testCase,a.DataAspectRatio,[1 1 1]);
    end
end
end

function ac=independentCentrifugal(latitude,ellipsoidalHeight)
% Direct WGS84 cylindrical distance, independent of the cached core helper.
a=6378137; f=1/298.257223563; omega=7.292115e-5;
nu=a./sqrt(1-f*(2-f)*sind(latitude).^2);
ac=omega^2*(nu+ellipsoidalHeight).*cosd(latitude);
ac(abs(latitude)==90)=0;
end

function snapshot=cacheSnapshot(path)
listing=dir(path);
if numel(listing)~=1, error('EnvironmentUITest:Cache','Expected a persisted environment cache.'); end
saved=load(path,'record');
snapshot=struct('bytes',listing.bytes,'modified',listing.datenum, ...
    'identity',saved.record.identity,'payloadSHA256',saved.record.payloadSHA256, ...
    'createdUTC',saved.record.createdUTC);
end

function verifyCapitalMarkers(testCase,a)
markers=findobj(a,'Tag','CapitalMarkers');
assertNumElements(testCase,markers,1);
verifyNumElements(testCase,markers.XData,197);
verifyNumElements(testCase,markers.YData,197);
verifyTrue(testCase,all(isfinite(markers.XData(:))) && all(isfinite(markers.YData(:))));
verifyTrue(testCase,markers.CData(1)>markers.CData(2) && markers.CData(1)>markers.CData(3));
boundaries=findobj(a,'Tag','CountryBoundaries');
assertNumElements(testCase,boundaries,1);
verifyGreaterThan(testCase,nnz(isfinite(boundaries.XData)),100);
end

function values=fieldValues(a,projection)
if strcmp(projection,'globe')
    field=findobj(a,'Tag','GravitySurface');
    values=double(field.CData);
else
    field=findobj(a,'Tag','GravityContours');
    values=double(field.ZData);
end
end

function selectCountry(fig,iso3)
search=control(fig,'CountrySearch'); search.Value=iso3; invoke(search,'ValueChangedFcn');
invoke(control(fig,'CountryList'),'ValueChangedFcn');
if ~strcmp(fig.UserData.iso3,iso3)
    error('EnvironmentUITest:Country','Unable to select %s.',iso3);
end
end

function setControl(fig,tag,value)
item=control(fig,tag);
if ~isequal(item.Value,value)
    item.Value=value; invoke(item,'ValueChangedFcn');
end
end

function item=control(fig,tag)
item=findobj(fig,'Tag',tag);
if numel(item)~=1, error('EnvironmentUITest:Control','Expected one control with Tag=%s.',tag); end
end

function showTab(fig,name)
tabs=control(fig,'ProjectionTabs');
tabs.SelectedTab=control(fig,name);
invoke(tabs,'SelectionChangedFcn');
end

function a=plotAxes(fig,name)
a=findobj(control(fig,name),'Type','axes');
end

function span=cameraSpan(a)
span=norm(a.CameraPosition-a.CameraTarget)*tand(a.CameraViewAngle/2);
end

function invoke(item,eventName)
callback=item.(eventName);
callback(item,[]);
drawnow;
end
