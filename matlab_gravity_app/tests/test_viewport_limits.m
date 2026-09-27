function tests=test_viewport_limits
%TEST_VIEWPORT_LIMITS Source-grid clipping without rendering or toolbox use.
tests=functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.TestData.originalPath=path;
addpath(fileparts(fileparts(mfilename('fullpath'))));
end

function teardownOnce(testCase)
path(testCase.TestData.originalPath);
end

function testOrdinaryLocalRangeIncludesRectangleCorners(testCase)
[x,y]=meshgrid(0:4,0:3); z=2*x+3*y;
[limits,info]=gravity_viewport_color_limits(x,y,z,[0.75 2.25],[0.5 2.5],[-10 30]);
% The affine field extrema occur at opposite view corners. Vertices alone
% would give [5,10] and incorrectly exclude the visible edge values.
verifyEqual(testCase,limits,[3 12],'AbsTol',1e-12);
verifyEqual(testCase,info.mode,'local');
verifyEqual(testCase,info.limits,limits);
verifyGreaterThan(testCase,info.sampleCount,4);
end

function testSubcellViewHasNoVerticesOrGridEdgeCrossings(testCase)
[x,y]=meshgrid(0:2,0:2); z=10*x+4*y;
[limits,info]=gravity_viewport_color_limits(x,y,z,[0.3 0.4],[0.25 0.35],[0 28]);
verifyEqual(testCase,limits,[4 5.4],'AbsTol',1e-12);
verifyEqual(testCase,info.mode,'local');
verifyEqual(testCase,info.sampleCount,4);
end

function testCurvedFootprintEdgeIntersectionAddsExtremum(testCase)
% A trapezoidal row grid has no source vertices inside this view. The two
% right view corners lie outside the map. The sloped map edge crossing the
% upper view boundary supplies the actual maximum (x=1.25, y=0.75).
x=[-2 0 2;-1 0 1]; y=[0 0 0;1 1 1]; z=x+2*y;
[limits,info]=gravity_viewport_color_limits(x,y,z,[0.8 1.8],[0.25 0.75],[-2 3]);
verifyEqual(testCase,limits,[1.3 2.75],'AbsTol',1e-12);
verifyEqual(testCase,info.mode,'local');
verifyGreaterThan(testCase,info.sampleCount,0);
end

function testMollweideBlankInsideBoundingBoxStaysEmpty(testCase)
[lon,lat]=meshgrid(-180:45:180,-90:30:90);
[x,y]=gravity_project(lon,lat,'mollweide'); z=lat;
% This rectangle is inside x/y's bounding box but beyond the narrow upper
% right map footprint. Clamping x into each row would invent local samples.
[limits,info]=gravity_viewport_color_limits(x,y,z,[2.5 2.7],[1.15 1.25],[-90 90]);
verifyEmpty(testCase,limits);
verifyEqual(testCase,info.mode,'empty');
verifyEmpty(testCase,info.limits);
verifyEqual(testCase,info.sampleCount,0);
end

function testFullViewUsesSuppliedGlobalRangeForEveryProjection(testCase)
[lon,lat]=meshgrid(-180:60:180,-80:40:80); z=lat+lon/10;
for projection={'miller','equirectangular','mercator','mollweide'}
    [x,y]=gravity_project(lon,lat,projection{1});
    [limits,info]=gravity_viewport_color_limits(x,y,z, ...
        [min(x(:))-0.1 max(x(:))+0.1],[min(y(:))-0.1 max(y(:))+0.1],[-123 456]);
    verifyEqual(testCase,limits,[-123 456]);
    verifyEqual(testCase,info.mode,'global');
    verifyEqual(testCase,info.limits,limits);
    verifyEqual(testCase,info.sampleCount,numel(z));
end
end

function testConstantZeroAndNonzeroProduceFiniteOrderedLimits(testCase)
[x,y]=meshgrid(0:2,0:2);
for constant=[0 9.8 -2]
    z=constant*ones(size(x));
    [limits,info]=gravity_viewport_color_limits(x,y,z,[0.2 0.3],[0.4 0.5],[-10 10]);
    verifyTrue(testCase,all(isfinite(limits)));
    verifyLessThan(testCase,limits(1),limits(2));
    verifyLessThanOrEqual(testCase,limits(1),constant);
    verifyGreaterThanOrEqual(testCase,limits(2),constant);
    verifyLessThan(testCase,diff(limits),1e-3);
    verifyEqual(testCase,info.mode,'local');
end
end

function testFewUlpDataAllowDistinctContourLevels(testCase)
[x,y]=meshgrid(0:1,0:1); z=10+eps(10)*[0 1;2 3];
[limits,info]=gravity_viewport_color_limits(x,y,z,[0.1 0.9],[0.1 0.9],[0 20]);
verifyEqual(testCase,info.mode,'local');
verifyTrue(testCase,all(diff(linspace(limits(1),limits(2),19))>0));
verifyLessThan(testCase,diff(limits),1e-10);
end

function testMollweideNearCollapsedPoleIsFinite(testCase)
[lon,lat]=meshgrid(-180:45:180,-90:30:90);
[x,y]=gravity_project(lon,lat,'mollweide'); z=y;
[limits,info]=gravity_viewport_color_limits(x,y,z,[-1e-5 1e-5], ...
    [sqrt(2)-0.01 sqrt(2)+0.01],[-sqrt(2) sqrt(2)]);
verifyEqual(testCase,info.mode,'local');
verifyEqual(testCase,limits,[sqrt(2)-0.01 sqrt(2)],'AbsTol',1e-12);
verifyTrue(testCase,all(isfinite(limits)));
verifyGreaterThan(testCase,info.sampleCount,0);
end

function testNoFiniteFieldValuesReturnEmpty(testCase)
[x,y]=meshgrid(0:2,0:2);
[limits,info]=gravity_viewport_color_limits(x,y,nan(size(x)),[0 2],[0 2],[-1 1]);
verifyEmpty(testCase,limits);
verifyEqual(testCase,info.mode,'empty');
verifyEqual(testCase,info.sampleCount,0);
end
