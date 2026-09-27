function [x,y] = gravity_project(lon,lat,projection)
%GRAVITY_PROJECT Toolbox-free world map projections, output in radians.
% longitude/latitude: degrees; scalars or equally sized arrays. NaNs split lines.
lambda = deg2rad(lon); phi = deg2rad(lat);
switch lower(char(projection))
    case {'miller','miller cylindrical'}
        x = lambda;
        y = 1.25 .* asinh(tan(0.8 .* phi));
    case {'equirectangular','plate carree'}
        x = lambda; y = phi;
    case 'mercator'
        x = lambda;
        clipped = min(max(phi,deg2rad(-85)),deg2rad(85));
        y = asinh(tan(clipped));
    case 'mollweide'
        theta = phi;
        interior = isfinite(phi) & abs(phi)<pi/2-1e-12;
        for k=1:30
            t = theta(interior);
            step = (2*t+sin(2*t)-pi*sin(phi(interior)))./(2+2*cos(2*t));
            theta(interior) = t-step;
            if isempty(step) || max(abs(step))<1e-12, break; end
        end
        theta(abs(phi)>=pi/2-1e-12) = sign(phi(abs(phi)>=pi/2-1e-12))*pi/2;
        x = (2*sqrt(2)/pi) .* lambda .* cos(theta);
        y = sqrt(2) .* sin(theta);
    otherwise
        error('gravity:Projection','Unknown projection: %s',projection);
end
end
