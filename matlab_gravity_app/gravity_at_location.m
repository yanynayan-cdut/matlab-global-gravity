function [g, detail] = gravity_at_location(latitude, longitude, height)
%GRAVITY_AT_LOCATION EGM2008 degree/order 180 effective gravity in m/s^2.
% Inputs: geodetic WGS84 latitude/longitude (degrees), ELLIPSOIDAL height (m).
% Height above mean sea level H is not the same quantity: h = H + geoid N.
% Coefficients are observed-data-derived EGM2008, not a synthetic perturbation.
% Acceleration includes Earth's rotation. No additional toolbox is needed.
arguments
    latitude double {mustBeReal,mustBeFinite,mustBeScalarOrEmpty}
    longitude double {mustBeReal,mustBeFinite,mustBeScalarOrEmpty}
    height double {mustBeReal,mustBeFinite,mustBeScalarOrEmpty} = 0
end
if isempty(latitude) || isempty(longitude) || isempty(height) || abs(latitude)>90
    error('GravityApp:Coordinates','Latitude must be in [-90,90]; inputs must be scalar.');
end
if height < -1000 || height > 100000
    error('GravityApp:Height','Supported ellipsoidal height range is -1000 to 100000 m.');
end
persistent model
if isempty(model)
    file = fullfile(fileparts(mfilename('fullpath')),'data','gravity_egm2008_n180_coefficients.mat');
    if ~isfile(file)
        error('GravityApp:MissingMeasuredData','Missing EGM2008 coefficients. Run scripts/rebuild_gravity_data.py; no synthetic fallback is used.');
    end
    model = load(file);
end
a=6378137; f=1/298.257223563; e2=f*(2-f); omega=7.292115e-5;
phi=deg2rad(latitude); lambda=deg2rad(mod(longitude+180,360)-180);
prime=a/sqrt(1-e2*sin(phi)^2);
rho=(prime+height)*cos(phi); z=(prime*(1-e2)+height)*sin(phi);
r=hypot(rho,z); phiC=atan2(z,rho); s=sin(phiC); c=cos(phiC);
N=double(model.degree); C=model.C; S=model.S;
orders=0:N; cl=cos(orders*lambda); sl=sin(orders*lambda);
p2=zeros(1,N+1); d2=p2; p1=p2; d1=p2; p1(1)=1;
sumR=-C(1,1); sumPhi=0; sumLambda=0;
for n=1:N
    p=zeros(1,N+1); d=p;
    if n==1, k=sqrt(3); else, k=sqrt((2*n+1)/(2*n)); end
    p(n+1)=k*c*p1(n); d(n+1)=k*(-s*p1(n)+c*d1(n));
    k=sqrt(2*n+1);
    p(n)=k*s*p1(n); d(n)=k*(c*p1(n)+s*d1(n));
    m=0:n-2; idx=m+1;
    aa=sqrt((2*n-1)*(2*n+1)./((n-m).*(n+m)));
    bb=sqrt((2*n+1)*(n+m-1).*(n-m-1)./((n-m).*(n+m)*(2*n-3)));
    p(idx)=aa.*s.*p1(idx)-bb.*p2(idx);
    d(idx)=aa.*(c*p1(idx)+s*d1(idx))-bb.*d2(idx);
    idx=1:n+1; m=0:n;
    hC=C(n+1,idx).*cl(idx)+S(n+1,idx).*sl(idx);
    q=(model.referenceRadius/r)^n;
    sumR=sumR-(n+1)*q*sum(p(idx).*hC);
    sumPhi=sumPhi+q*sum(d(idx).*hC);
    sumLambda=sumLambda+q*sum(m.*p(idx).*(-C(n+1,idx).*sl(idx)+S(n+1,idx).*cl(idx)));
    p2=p1; p1=p; d2=d1; d1=d;
end
gr=model.GM/r^2*sumR+omega^2*r*c^2;
gp=model.GM/r^2*sumPhi-omega^2*r*s*c;
gl=model.GM/r^2*sumLambda/c;
g=sqrt(gr^2+gp^2+gl^2);
normal=9.7803253359*(1+0.00193185265241*sin(phi)^2)/sqrt(1-e2*sin(phi)^2);
mRot=omega^2*a^2*(a*(1-f))/3.986004418e14;
normal=normal*(1-2/a*(1+f+mRot-2*f*sin(phi)^2)*height+3/a^2*height^2);
detail=struct('normalGravity',normal,'disturbance',g-normal, ...
    'disturbanceMgal',(g-normal)*1e5,'model','EGM2008', 'degree',N, ...
    'heightReference','WGS84 ellipsoidal height (m)', 'latitude',latitude, ...
    'longitude',longitude,'height',height, 'radius',r, ...
    'radialAcceleration',gr,'latitudinalAcceleration',gp,'longitudinalAcceleration',gl);
end
