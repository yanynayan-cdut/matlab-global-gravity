function tests = test_gravity_physics
%TEST_GRAVITY_PHYSICS Physics and numerical-regression checks for the app.
% Run from matlab_gravity_app with: results = runtests("tests").

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
testCase.TestData.root = root;
end

function teardownOnce(testCase)
root = testCase.TestData.root;
rmpath(root);
end

function testMeasuredModelFilesPresent(testCase)
root = testCase.TestData.root;
coef = fullfile(root, 'data', 'gravity_egm2008_n180_coefficients.mat');
gridA = fullfile(root, 'data', 'gravity_grid.mat');
gridB = fullfile(root, 'data', 'egm2008_grid.mat');
assumeTrue(testCase, isfile(coef), 'Measured EGM2008 coefficient bundle is not generated yet.');
assumeTrue(testCase, isfile(gridA) || isfile(gridB), 'Measured EGM2008 grid is not generated yet.');
end

function testWgs84NormalGravityReference(testCase)
assumeTrue(testCase, hasGravityData(testCase));
[g0, d0] = gravity_at_location(0, 0, 0); %#ok<ASGLU>
[g45, d45] = gravity_at_location(45, 0, 0); %#ok<ASGLU>
[g90, d90] = gravity_at_location(90, 0, 0); %#ok<ASGLU>
expected = [9.7803253359, 9.8061977694, 9.8321849378];
actual = [d0.normalGravity, d45.normalGravity, d90.normalGravity];
verifyEqual(testCase, actual, expected, 'AbsTol', 2e-9);
verifyGreaterThan(testCase, [g0 g45 g90], 9.7);
verifyLessThan(testCase, [g0 g45 g90], 9.9);
end

function testLongitudePeriodicity(testCase)
assumeTrue(testCase, hasGravityData(testCase));
[g1, d1] = gravity_at_location(23.4, -180, 0); %#ok<ASGLU>
[g2, d2] = gravity_at_location(23.4, 180, 0); %#ok<ASGLU>
[g3, d3] = gravity_at_location(23.4, 540, 0); %#ok<ASGLU>
verifyEqual(testCase, g1, g2, 'AbsTol', 2e-10);
verifyEqual(testCase, g2, g3, 'AbsTol', 2e-10);
verifyEqual(testCase, d1.disturbance, d2.disturbance, 'AbsTol', 2e-10);
verifyEqual(testCase, d2.disturbance, d3.disturbance, 'AbsTol', 2e-10);
end

function testFinitePositiveGravityAtPolesAndEquator(testCase)
assumeTrue(testCase, hasGravityData(testCase));
locations = [-90 0; -89.999 120; 0 0; 45 179.999; 90 0];
for k = 1:size(locations, 1)
    [g, detail] = gravity_at_location(locations(k,1), locations(k,2), 0); %#ok<ASGLU>
    verifyTrue(testCase, isfinite(g));
    verifyGreaterThan(testCase, g, 9.6);
    verifyLessThan(testCase, g, 10.0);
    verifyTrue(testCase, all(isfinite([detail.radialAcceleration, detail.latitudinalAcceleration, detail.longitudinalAcceleration])));
end
end

function testFreeAirHeightScale(testCase)
assumeTrue(testCase, hasGravityData(testCase));
[g0, ~] = gravity_at_location(30, 10, 0);
[g1, ~] = gravity_at_location(30, 10, 1000);
% Free-air gradient is approximately -0.3086 mGal/m = -3.086e-6 m/s^2/m.
delta = g1 - g0;
verifyLessThan(testCase, delta, -2.0e-3);
verifyGreaterThan(testCase, delta, -4.2e-3);
end

function testInverseSquareLawSanity(testCase)
% Independent reference check for the Newtonian point-mass limit.
GM = 3.986004418e14; R = 6378137.0;
g = GM / R^2;
verifyEqual(testCase, g, 9.798285479, 'AbsTol', 2e-6);
verifyEqual(testCase, (GM/(R+1000)^2) / g, (R/(R+1000))^2, 'AbsTol', 1e-13);
end

function testIndependentPotentialGradientReference(testCase)
assumeTrue(testCase, hasGravityData(testCase));
% Golden values come from SciPy assoc_legendre_p_all, not the app's
% recurrence: evaluate total potential then independently differentiate in
% r/latitude/longitude. Reproduce with independent_gravity_reference.py.
points = [39.9042 116.4074 0; 0 0 0; 45 100 0; 80 -130 0; -50 110 1000];
expected = [9.801478154823732; 9.780321696832960; 9.805800142973052; ...
    9.830405506372403; 9.807523794081540];
for k = 1:size(points,1)
    g = gravity_at_location(points(k,1), points(k,2), points(k,3));
    verifyEqual(testCase, g, expected(k), 'AbsTol', 2e-8);
end
end

function testProjectionApiIfAvailable(testCase)
assumeTrue(testCase, exist('gravity_project', 'file') == 2, 'gravity_project.m is not available yet.');
lon = [-180 -90 0 90 180]; lat = [-80 -20 0 20 80];
names = {'Miller','Equirectangular','Mercator','Mollweide'};
for i = 1:numel(names)
    [x, y] = gravity_project(lon, lat, names{i});
    verifySize(testCase, x, size(lon));
    verifySize(testCase, y, size(lat));
    verifyTrue(testCase, all(isfinite(x(:))));
    verifyTrue(testCase, all(isfinite(y(:))));
    % Map x coordinates have a branch cut; -180 and +180 stay at opposite
    % edges. Odd symmetry, rather than periodic x, is the right invariant.
    [x2, y2] = gravity_project(-lon, -lat, names{i});
    verifyEqual(testCase, x, -x2, 'AbsTol', 1e-10);
    verifyEqual(testCase, y, -y2, 'AbsTol', 1e-10);
    [x0, y0] = gravity_project(0, 0, names{i});
    verifyEqual(testCase, [x0 y0], [0 0], 'AbsTol', 1e-14);
end
[x, y] = gravity_project([180 NaN -180], [90 NaN -90], 'Mollweide');
verifyEqual(testCase, x([1 3]), [0 0], 'AbsTol', 1e-14);
verifyEqual(testCase, y([1 3]), sqrt(2)*[1 -1], 'AbsTol', 1e-14);
verifyTrue(testCase, isnan(x(2)) && isnan(y(2)));
[x, y] = gravity_project(30, 45, 'Miller');
verifyEqual(testCase, [x y], [pi/6, 1.25*log(tan(pi/4+0.4*pi/4))], 'AbsTol', 1e-14);
end

function tf = hasGravityData(testCase)
root = testCase.TestData.root;
tf = exist('gravity_at_location', 'file') == 2 && ...
    isfile(fullfile(root, 'data', 'gravity_egm2008_n180_coefficients.mat'));
end
