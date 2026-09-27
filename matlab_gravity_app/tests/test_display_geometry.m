function tests=test_display_geometry
tests=functiontests(localfunctions);
end
function setupOnce(testCase)
root=fileparts(fileparts(mfilename('fullpath'))); addpath(root);
testCase.TestData.root=root;
testCase.TestData.grid=load(fullfile(root,'data','gravity_grid.mat'));
testCase.TestData.geo=load(fullfile(root,'data','world_geodata.mat'), ...
    'boundaryLatitude','boundaryLongitude');
end
function teardownOnce(testCase)
rmpath(testCase.TestData.root);
end
function out=geometry(testCase,quality)
g=testCase.TestData.grid; b=testCase.TestData.geo;
out=gravity_display_geometry(g.lat,g.lon,g.g,b.boundaryLatitude,b.boundaryLongitude,quality);
end
function testFinePreservesOriginalValues(testCase)
out=geometry(testCase,'fine'); g=testCase.TestData.grid; b=testCase.TestData.geo;
verifyEqual(testCase,out.values,g.g);
verifyEqual(testCase,out.lat,g.lat(:)); verifyEqual(testCase,out.lon,g.lon(:)');
verifyEqual(testCase,out.boundaryLatitude(isfinite(out.boundaryLatitude)), ...
    b.boundaryLatitude(isfinite(b.boundaryLatitude)));
verifyEqual(testCase,out.boundaryLongitude(isfinite(out.boundaryLongitude)), ...
    b.boundaryLongitude(isfinite(b.boundaryLongitude)));
end
function testLowerDetailAndUnchangedSamples(testCase)
g=testCase.TestData.grid;
for q={'balanced','fast'}
    out=geometry(testCase,q{1});
    verifyEqual(testCase,out.values,g.g(out.rowIndex,out.columnIndex));
    verifyLessThan(testCase,numel(out.values),0.27*numel(g.g));
    verifyLessThan(testCase,out.metadata.displayBoundaryVertices,0.4*out.metadata.sourceBoundaryVertices);
    verifyEqual(testCase,out.lat([1 end]),[-90;90]);
    verifyEqual(testCase,out.lon([1 end]),[-180 180]);
    verifyTrue(testCase,all(ismember([-85 85],out.lat)));
end
end
function testEveryBoundaryComponentAndEndpointSurvives(testCase)
b=testCase.TestData.geo;
original=[b.boundaryLongitude b.boundaryLatitude];
[starts,stops]=components(original);
for q={'balanced','fast'}
    out=geometry(testCase,q{1}); reduced=[out.boundaryLongitude out.boundaryLatitude];
    [first,last]=components(reduced);
    verifyEqual(testCase,numel(first),numel(starts));
    verifyEqual(testCase,reduced(first,:),original(starts,:),'AbsTol',1e-12);
    verifyEqual(testCase,reduced(last,:),original(stops,:),'AbsTol',1e-12);
    verifyTrue(testCase,all(isnan(reduced(:,1))==isnan(reduced(:,2))));
end
end
function testDatelineDoesNotJoinOppositeEdges(testCase)
out=gravity_display_geometry([-90;0;90],[-180 0 180],ones(3), ...
    [10;11;12;13],[170;179;-179;-170],'fast');
[starts,stops]=components([out.boundaryLongitude out.boundaryLatitude]);
verifyEqual(testCase,numel(starts),2);
verifyEqual(testCase,out.boundaryLongitude(starts),[170;-179]);
verifyEqual(testCase,out.boundaryLongitude(stops),[179;-170]);
end
function testTinyIslandsAndRingClosureRemain(testCase)
bl=[0;0;0.01;0;NaN;5;5;5.005;5;NaN];
bo=[0;0.01;0;0;NaN;5;5.005;5;5;NaN];
out=gravity_display_geometry([-90;0;90],[-180 0 180],ones(3),bl,bo,'fast');
verifyEqual(testCase,out.boundaryLatitude,bl);
verifyEqual(testCase,out.boundaryLongitude,bo);
end
function [first,last]=components(points)
valid=all(isfinite(points),2); edges=diff([false;valid;false]);
first=find(edges==1); last=find(edges==-1)-1;
end
