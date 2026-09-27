function tests = test_gravity_ui
%TEST_GRAVITY_UI Exercise app controls and five rendered map views.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root);
testCase.TestData.root=root;
testCase.TestData.figure=gravity_field_app('Visible','off');
drawnow;
end

function teardownOnce(testCase)
if isfield(testCase.TestData,'figure') && isgraphics(testCase.TestData.figure)
    delete(testCase.TestData.figure);
end
rmpath(testCase.TestData.root);
end

function testCompleteCountryListAndRedMarkers(testCase)
fig=testCase.TestData.figure;
list=findobj(fig,'Tag','CountryList');
search=findobj(fig,'Tag','CountrySearch');
search.Value=''; invoke(search,'ValueChangedFcn');
verifyNumElements(testCase,list.Items,197);
verifyNumElements(testCase,unique(list.ItemsData),197);
% The approved additional records must be present in the default set.
for query={'VAT','PSE','COK','NIU'}
    search.Value=query{1}; invoke(search,'ValueChangedFcn');
    verifyNumElements(testCase,list.Items,1);
    verifyEqual(testCase,fig.UserData.iso3,query{1});
end
search.Value=''; invoke(search,'ValueChangedFcn');
showTab(fig,'globe');
axesHandle=plotAxes(fig,'globe');
markers=findobj(axesHandle,'Tag','CapitalMarkers');
verifyNumElements(testCase,markers.XData,197);
verifyTrue(testCase,all(isfinite(markers.XData)));
verifyTrue(testCase,markers.CData(1)>markers.CData(2));
verifyTrue(testCase,markers.CData(1)>markers.CData(3));
end

function testSearchSelectionAndEmptyResult(testCase)
fig=testCase.TestData.figure;
search=findobj(fig,'Tag','CountrySearch'); list=findobj(fig,'Tag','CountryList');
for query={'中国','北京','Beijing','CHN'}
    search.Value=query{1}; invoke(search,'ValueChangedFcn');
    verifyNumElements(testCase,list.Items,1);
    invoke(list,'ValueChangedFcn');
    verifyEqual(testCase,fig.UserData.iso3,'CHN');
end
search.Value='JPN'; invoke(search,'ValueChangedFcn');
verifyNumElements(testCase,list.Items,1);
invoke(list,'ValueChangedFcn');
verifyEqual(testCase,fig.UserData.iso3,'JPN');
search.Value='__no_country_exists__'; invoke(search,'ValueChangedFcn');
verifyEqual(testCase,list.ItemsData,0);
invoke(list,'ValueChangedFcn');
verifyEqual(testCase,fig.UserData.iso3,'JPN');
search.Value=''; invoke(search,'ValueChangedFcn');
verifyNumElements(testCase,list.Items,197);
end

function testCalculatorMassAndAltitude(testCase)
fig=testCase.TestData.figure;
mass=findobj(fig,'Tag','Mass'); altitude=findobj(fig,'Tag','Altitude');
mass.Value=60; altitude.Value=0; invoke(mass,'ValueChangedFcn');
state0=fig.UserData;
verifyEqual(testCase,state0.force,60*state0.g,'AbsTol',1e-10);
mass.Value=120; invoke(mass,'ValueChangedFcn');
verifyEqual(testCase,fig.UserData.force,2*state0.force,'AbsTol',1e-10);
altitude.Value=1000; invoke(altitude,'ValueChangedFcn');
verifyLessThan(testCase,fig.UserData.g,state0.g);
mass.Value=70; altitude.Value=0; invoke(mass,'ValueChangedFcn');
end

function testTransparentRadialReliefAndBoundaries(testCase)
fig=testCase.TestData.figure; showTab(fig,'globe');
axesHandle=plotAxes(fig,'globe');
opacity=findobj(fig,'Tag','Opacity'); relief=findobj(fig,'Tag','Relief');
opacity.Value=0.55; invoke(opacity,'ValueChangedFcn');
surface=findobj(axesHandle,'Tag','GravitySurface');
verifyEqual(testCase,surface.FaceAlpha,0.55,'AbsTol',1e-14);
r=sqrt(surface.XData.^2+surface.YData.^2+surface.ZData.^2);
verifyGreaterThan(testCase,max(r(:))-min(r(:)),0.05);
verifyNumElements(testCase,findobj(axesHandle,'Tag','CountryBoundaries'),1);
verifyNumElements(testCase,findobj(axesHandle,'Tag','GravityContours'),1);
relief.Value=0; invoke(relief,'ValueChangedFcn');
surface=findobj(axesHandle,'Tag','GravitySurface');
r=sqrt(surface.XData.^2+surface.YData.^2+surface.ZData.^2);
verifyLessThan(testCase,max(r(:))-min(r(:)),1e-12);
relief.Value=relief.Limits(2); invoke(relief,'ValueChangedFcn');
surface=findobj(axesHandle,'Tag','GravitySurface');
r=sqrt(surface.XData.^2+surface.YData.^2+surface.ZData.^2);
verifyGreaterThan(testCase,max(r(:))-min(r(:)),0.3);
for v=opacity.Limits
    opacity.Value=v; invoke(opacity,'ValueChangedFcn');
    surface=findobj(axesHandle,'Tag','GravitySurface');
    verifyEqual(testCase,surface.FaceAlpha,v,'AbsTol',1e-14);
end
relief.Value=0.16; invoke(relief,'ValueChangedFcn');
opacity.Value=0.78; invoke(opacity,'ValueChangedFcn');
end

function testMapClickAndFieldSwitch(testCase)
fig=testCase.TestData.figure; showTab(fig,'globe');
axesHandle=plotAxes(fig,'globe');
markers=findobj(axesHandle,'Tag','CapitalMarkers');
index=17;
point=[markers.XData(index),markers.YData(index),markers.ZData(index)];
callback=markers.ButtonDownFcn;
callback(markers,struct('IntersectionPoint',point)); drawnow;
list=findobj(fig,'Tag','CountryList');
verifyEqual(testCase,list.Value,index);
state0=fig.UserData;
mode=findobj(fig,'Tag','FieldMode'); mode.Value='gravity'; invoke(mode,'ValueChangedFcn');
surface=findobj(axesHandle,'Tag','GravitySurface');
verifyGreaterThan(testCase,min(surface.CData(:)),9.7);
verifyLessThan(testCase,max(surface.CData(:)),9.9);
% Switching display quantity must not alter calculator's physical result.
verifyEqual(testCase,fig.UserData.g,state0.g,'AbsTol',1e-14);
mode.Value='disturbance'; invoke(mode,'ValueChangedFcn');
end

function testAllProjectionTabsRender(testCase)
fig=testCase.TestData.figure;
names={'globe','miller','equirectangular','mercator','mollweide'};
for i=1:numel(names)
    showTab(fig,names{i});
    axesHandle=plotAxes(fig,names{i});
    markers=findobj(axesHandle,'Tag','CapitalMarkers');
    verifyNumElements(testCase,markers.XData,197);
    verifyTrue(testCase,all(isfinite(markers.XData)));
    verifyTrue(testCase,all(isfinite(markers.YData)));
    boundaries=findobj(axesHandle,'Tag','CountryBoundaries');
    verifyNumElements(testCase,boundaries,1);
    verifyGreaterThan(testCase,sum(isfinite(boundaries.XData(:))),10000);
end
showTab(fig,'globe');
end

function showTab(fig,name)
tabs=findobj(fig,'Tag','ProjectionTabs');
tabs.SelectedTab=findobj(fig,'Tag',name);
invoke(tabs,'SelectionChangedFcn');
end

function a=plotAxes(fig,name)
tab=findobj(fig,'Tag',name);
a=findobj(tab,'Type','axes');
end

function invoke(control,eventName)
callback=control.(eventName);
callback(control,[]);
drawnow;
end
