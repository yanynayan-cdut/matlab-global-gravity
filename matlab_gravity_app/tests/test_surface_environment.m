function tests = test_surface_environment
%TEST_SURFACE_ENVIRONMENT Rotation physics, source policy, and disk cache.
% Fixtures are explicitly synthetic test inputs, never application data.
tests=functiontests(localfunctions);
end

function setupOnce(testCase)
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root);
testCase.TestData.root=root;
end

function teardownOnce(testCase)
clear load_surface_environment;
rmpath(testCase.TestData.root);
end

function setup(testCase)
clear load_surface_environment;
directory=tempname;
mkdir(directory);
testCase.TestData.directory=directory;
testCase.TestData.source=fullfile(directory,'terrain_test_fixture.mat');
testCase.TestData.cache=fullfile(directory,'centrifugal_test_cache.mat');
fixture=createFixture();
save(testCase.TestData.source,'-struct','fixture','-v7');
end

function teardown(testCase)
clear load_surface_environment;
% This test owns this freshly-created tempname directory and no other path.
if isfolder(testCase.TestData.directory), rmdir(testCase.TestData.directory,'s'); end
end

function testEquatorPolesAndMass(testCase)
[a,d]=centrifugal_at_location(0,0,70);
omega=7.292115e-5;
verifyEqual(testCase,a,omega^2*6378137,'RelTol',1e-14);
verifyEqual(testCase,d.rho,6378137);
verifyEqual(testCase,d.force,70*a,'RelTol',1e-14);
verifyTrue(testCase,d.alreadyIncludedInEffectiveGravity);
[atPoles,dp]=centrifugal_at_location([-90 90],[0 9000],70);
verifyEqual(testCase,atPoles,[0 0]);
verifyEqual(testCase,dp.rho,[0 0]);
verifyEqual(testCase,dp.heightSlope,[0 0]);
verifyEqual(testCase,dp.force,[0 0]);
verifyGreaterThan(testCase,centrifugal_at_location(89.999,0),0);
end

function testVectorizedHeightDerivative(testCase)
latitude=[-90;0;45;90];
height=[-500 0 1000];
[a,d]=centrifugal_at_location(latitude,height,70);
verifySize(testCase,a,[4 3]);
verifyEqual(testCase,d.force,70*a,'AbsTol',1e-14);
verifyEqual(testCase,a(:,3)-a(:,2),d.heightSlope*1000,'AbsTol',1e-16);
verifyEqual(testCase,d.rho(2,:),6378137+height,'AbsTol',1e-9);
[~,zeroMass]=centrifugal_at_location(30,100,0);
verifyEqual(testCase,zeroMass.force,0);
end

function testInvalidPhysicalInputs(testCase)
verifyError(testCase,@()centrifugal_at_location(91,0),'GravityApp:CentrifugalLatitude');
verifyError(testCase,@()centrifugal_at_location(0,0,-1),'GravityApp:CentrifugalMass');
verifyError(testCase,@()centrifugal_at_location(0,-6378137),'GravityApp:CentrifugalHeight');
verifyError(testCase,@()centrifugal_at_location(zeros(2),zeros(3)), ...
    'GravityApp:CentrifugalDimensions');
end

function testDiskAndMemoryReuse(testCase)
[first,created]=loadFixture(testCase);
verifyEqual(testCase,created.status,'computed');
verifyTrue(testCase,created.written);
verifyTrue(testCase,isfile(testCase.TestData.cache));
bytesBefore=readBytes(testCase.TestData.cache);
verifyEqual(testCase,first.hSurface,first.elevationM+first.geoidUndulationM);
verifyEqual(testCase,first.capitalHSurface,first.capitalElevationM+first.capitalGeoidM);
verifyLessThan(testCase,first.elevationM(2,1),0); % preserve source seafloor
verifyEqual(testCase,first.oceanPolicy,'seafloor');
verifyFalse(testCase,first.approximation.applied);
[second,memory]=loadFixture(testCase);
verifyEqual(testCase,memory.status,'memory');
verifyFalse(testCase,memory.recomputed);
verifyEqual(testCase,second.acSurface,first.acSurface);
clear load_surface_environment;
[third,disk]=loadFixture(testCase);
verifyEqual(testCase,disk.status,'disk');
verifyFalse(testCase,disk.written);
verifyEqual(testCase,third.acSurface,first.acSurface);
verifyEqual(testCase,readBytes(testCase.TestData.cache),bytesBefore);
verifyEqual(testCase,third.capitalAcSurface, ...
    centrifugal_at_location(third.capitalLatitude,third.capitalHSurface),'AbsTol',1e-15);
relativeHeight=1200;
verifyEqual(testCase,third.capitalAcSurface+relativeHeight*third.capitalAcHeightSlope, ...
    centrifugal_at_location(third.capitalLatitude,third.capitalHSurface+relativeHeight), ...
    'AbsTol',1e-15);
end

function testSourceHashInvalidatesMemoryAndDisk(testCase)
[before,infoBefore]=loadFixture(testCase);
fixture=load(testCase.TestData.source);
fixture.elevationM(2,2)=fixture.elevationM(2,2)+250;
fixture.capitalElevationM(1)=fixture.capitalElevationM(1)+100;
save(testCase.TestData.source,'-struct','fixture','-v7');
[after,infoAfter]=loadFixture(testCase);
verifyEqual(testCase,infoAfter.status,'computed');
verifyNotEqual(testCase,infoAfter.sourceSHA256,infoBefore.sourceSHA256);
verifyEqual(testCase,after.acSurface(2,2)-before.acSurface(2,2), ...
    250*before.acHeightSlope(2,2),'AbsTol',1e-15);
verifyEqual(testCase,after.capitalAcSurface(1)-before.capitalAcSurface(1), ...
    100*before.capitalAcHeightSlope(1),'AbsTol',1e-15);
clear load_surface_environment;
[~,reused]=loadFixture(testCase);
verifyEqual(testCase,reused.status,'disk');
end

function testCorruptCacheChecksumAndShapeRecover(testCase)
[expected,~]=loadFixture(testCase);
saved=load(testCase.TestData.cache,'record');
for corruption=1:3
    record=saved.record;
    if corruption==1
        record.payload.acSurface(2,2)=record.payload.acSurface(2,2)+0.01;
    elseif corruption==2
        record.payload.acSurface=record.payload.acSurface(:,1:2);
    else
        record.payload.capitalAcSurface(1)=NaN;
    end
    save(testCase.TestData.cache,'record','-v7');
    clear load_surface_environment;
    [actual,info]=loadFixture(testCase);
    verifyEqual(testCase,info.status,'computed');
    verifyEqual(testCase,actual.acSurface,expected.acSurface);
    verifyEqual(testCase,actual.capitalAcSurface,expected.capitalAcSurface);
end
end

function testCacheVersionConstantsAndPolicyInvalidate(testCase)
loadFixture(testCase);
saved=load(testCase.TestData.cache,'record');
for mutation=1:3
    record=saved.record;
    if mutation==1
        record.identity.schemaVersion=0;
    elseif mutation==2
        record.identity.constants.omegaRadPerSecond=1;
    else
        record.identity.oceanPolicy='sea_surface';
    end
    save(testCase.TestData.cache,'record','-v7');
    clear load_surface_environment;
    [~,info]=loadFixture(testCase);
    verifyEqual(testCase,info.status,'computed');
end
% Even when all N values are present, a different declared policy must have
% its own cache identity rather than accidentally reusing the previous one.
[~,info]=loadFixture(testCase,'GeoidPolicy','assume_zero');
verifyEqual(testCase,info.status,'computed');
end

function testMissingGeoidRequiresExplicitApproximation(testCase)
fixture=load(testCase.TestData.source);
fixture=rmfield(fixture,{'geoidUndulationM','capitalGeoidM'});
save(testCase.TestData.source,'-struct','fixture','-v7');
verifyError(testCase,@()loadFixture(testCase),'GravityApp:MissingGeoid');
[approximation,info]=loadFixture(testCase,'GeoidPolicy','assume_zero');
verifyTrue(testCase,approximation.approximation.applied);
verifyTrue(testCase,info.geoidApproximationApplied);
verifyTrue(testCase,all(isnan(approximation.geoidUndulationM(:))));
verifyTrue(testCase,all(isnan(approximation.capitalGeoidM(:))));
verifyEqual(testCase,approximation.geoidUsedM,zeros(size(approximation.elevationM)));
verifyEqual(testCase,approximation.hSurface,approximation.elevationM);
verifyEqual(testCase,approximation.capitalHSurface,approximation.capitalElevationM);
verifyError(testCase,@()loadFixture(testCase),'GravityApp:MissingGeoid');
end

function testMissingElevationCannotBeApproximated(testCase)
fixture=load(testCase.TestData.source);
fixture.elevationM(1,1)=NaN;
save(testCase.TestData.source,'-struct','fixture','-v7');
verifyError(testCase,@()loadFixture(testCase,'GeoidPolicy','assume_zero'), ...
    'GravityApp:TerrainValues');
end

function testExplicitCacheCannotOverwriteSource(testCase)
verifyError(testCase,@()load_surface_environment('SourceFile',testCase.TestData.source, ...
    'CacheFile',testCase.TestData.source),'GravityApp:CachePath');
end

function testMissingSourceNeverFallsBackToCache(testCase)
loadFixture(testCase);
delete(testCase.TestData.source);
verifyError(testCase,@()loadFixture(testCase),'GravityApp:MissingTerrainData');
end

function [environment,info]=loadFixture(testCase,varargin)
[environment,info]=load_surface_environment('SourceFile',testCase.TestData.source, ...
    'CacheFile',testCase.TestData.cache,varargin{:});
end

function fixture=createFixture()
fixture=struct('lat',[-90 0 90],'lon',[-180 0 180], ...
    'elevationM',[0 5 10;-1500 300 600;100 105 110], ...
    'geoidUndulationM',[2 3 4;15 20 25;-2 -3 -4]);
n=197;
codes=cell(n,1);
for k=1:n
    codes{k}=['T' char(65+floor((k-1)/26)) char(65+mod(k-1,26))];
end
fixture.capitalIso3=codes;
fixture.capitalLatitude=linspace(-70,70,n)';
fixture.capitalLongitude=linspace(-175,175,n)';
fixture.capitalElevationM=(0:n-1)';
fixture.capitalGeoidM=ones(n,1)*20;
end

function bytes=readBytes(path)
fid=fopen(path,'rb');
finish=onCleanup(@()fclose(fid)); %#ok<NASGU>
bytes=fread(fid,Inf,'*uint8');
end
