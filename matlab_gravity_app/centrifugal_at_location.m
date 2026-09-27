function [acceleration,detail] = centrifugal_at_location(latitude,ellipsoidalHeight,mass)
%CENTRIFUGAL_AT_LOCATION WGS84 centrifugal acceleration and force magnitudes.
%   [AC,DETAIL] = centrifugal_at_location(PHI,H,M) accepts geodetic latitude
%   PHI (degrees), WGS84 ellipsoidal height H (m), and mass M (kg, default 1).
%   Scalar expansion and compatible array sizes are supported. AC is in
%   m/s^2 and DETAIL.force is in N. Orthometric height must first be converted
%   with h = H_orthometric + geoid undulation N.
%
%   AC points away from the rotation axis, not generally along the local
%   vertical. It is already included in gravity_at_location's effective g;
%   DO NOT subtract it from or add it to that gravity result a second time.
if nargin<3, mass=1; end
validateattributes(latitude,{'numeric'},{'real','finite','nonempty'},mfilename,'latitude');
validateattributes(ellipsoidalHeight,{'numeric'},{'real','finite','nonempty'},mfilename,'ellipsoidalHeight');
validateattributes(mass,{'numeric'},{'real','finite','nonempty'},mfilename,'mass');
latitude=double(latitude); ellipsoidalHeight=double(ellipsoidalHeight); mass=double(mass);
if any(abs(latitude(:))>90)
    error('GravityApp:CentrifugalLatitude','Latitude must be within [-90,90] degrees.');
end
if any(mass(:)<0)
    error('GravityApp:CentrifugalMass','Mass must be nonnegative.');
end
a=6378137; f=1/298.257223563; e2=f*(2-f); omega=7.292115e-5;
cosLatitude=cosd(latitude);
% Make both poles exactly zero, without zeroing nearby finite latitudes.
cosLatitude(abs(latitude)==90)=0;
primeVerticalRadius=a./sqrt(1-e2*sind(latitude).^2);
try
    distance=primeVerticalRadius+ellipsoidalHeight;
    rho=distance.*cosLatitude;
catch exception
    error('GravityApp:CentrifugalDimensions','Latitude and height sizes are incompatible: %s',exception.message);
end
if any(distance(:)<=0)
    error('GravityApp:CentrifugalHeight','Height must leave a positive distance from the ellipsoid curvature center.');
end
acceleration=omega^2*rho;
try
    force=mass.*acceleration;
catch exception
    error('GravityApp:CentrifugalDimensions','Mass and acceleration sizes are incompatible: %s',exception.message);
end
if any(~isfinite(rho(:))) || any(~isfinite(acceleration(:))) || any(~isfinite(force(:)))
    error('GravityApp:CentrifugalOverflow','Inputs produced nonfinite distance, acceleration, or force.');
end
constants=struct('semiMajorAxisM',a,'flattening',f,'eccentricitySquared',e2, ...
    'omegaRadPerSecond',omega);
detail=struct('rho',rho,'force',force,'omega',omega,'mass',mass, ...
    'latitude',latitude,'ellipsoidalHeight',ellipsoidalHeight, ...
    'primeVerticalRadiusM',primeVerticalRadius,'heightSlope',omega^2*cosLatitude, ...
    'constants',constants,'accelerationUnit','m/s^2','forceUnit','N', ...
    'heightReference','WGS84 ellipsoidal height; h = orthometric H + geoid N', ...
    'direction','Away from the Earth rotation axis', ...
    'alreadyIncludedInEffectiveGravity',true);
end
