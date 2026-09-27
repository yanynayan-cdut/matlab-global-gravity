function [limits,info] = gravity_viewport_color_limits(x,y,z,xLimits,yLimits,globalLimits)
%GRAVITY_VIEWPORT_COLOR_LIMITS Color limits of a visible projected contour grid.
% x/y/z are equally sized contourf matrices. y is constant along each row,
% row y increases, and x increases along each row (collapsed poles allowed).
% Only source vertices, clipped grid-edge intersections, and the four view
% corners are sampled. No new dense grid or scattered interpolant is built.
% info.sampleCount counts finite candidate values, including coincident ones.
% A view outside the actual map returns []/'empty'; the caller keeps its CLim.

validateattributes(x,{'numeric'},{'real','2d','nonempty','finite'},mfilename,'x');
validateattributes(y,{'numeric'},{'real','2d','nonempty','finite'},mfilename,'y');
validateattributes(z,{'numeric'},{'real','2d','nonempty'},mfilename,'z');
if ~isequal(size(x),size(y),size(z))
    error('gravity:ViewportGrid','x, y and z must be equally sized contour grids.');
end
x=double(x); y=double(y); z=double(z);
xLimits=orderedPair(xLimits,'xLimits');
yLimits=orderedPair(yLimits,'yLimits');
globalLimits=orderedPair(globalLimits,'globalLimits');
limits=[];
info=struct('mode','empty','limits',[],'sampleCount',0);
finiteValues=isfinite(z);
if ~any(finiteValues(:)), return; end

extent=[min(x(:)),max(x(:)),min(y(:)),max(y(:))];
xTolerance=32*eps(max(1,max(abs([extent(1:2),xLimits]))));
yTolerance=32*eps(max(1,max(abs([extent(3:4),yLimits]))));
if xLimits(2)<extent(1)-xTolerance || xLimits(1)>extent(2)+xTolerance || ...
        yLimits(2)<extent(3)-yTolerance || yLimits(1)>extent(4)+yTolerance
    return
end
if xLimits(1)<=extent(1)+xTolerance && xLimits(2)>=extent(2)-xTolerance && ...
        yLimits(1)<=extent(3)+yTolerance && yLimits(2)>=extent(4)-yTolerance
    limits=usableLimits(globalLimits);
    info=struct('mode','global','limits',limits,'sampleCount',nnz(finiteValues));
    return
end

visible=finiteValues & x>=xLimits(1)-xTolerance & x<=xLimits(2)+xTolerance & ...
    y>=yLimits(1)-yTolerance & y<=yLimits(2)+yTolerance;
samples=z(visible);

% Horizontal row edges and the straight sides between adjacent projected
% rows describe the actual curvilinear quadrilateral mesh boundary as well
% as its internal grid lines. Intersect all four sides of the view rectangle.
samples=[samples; edgeSamples(x(:,1:end-1),y(:,1:end-1),z(:,1:end-1), ...
    x(:,2:end),y(:,2:end),z(:,2:end),xLimits,yLimits,xTolerance,yTolerance)]; %#ok<AGROW>
samples=[samples; edgeSamples(x(1:end-1,:),y(1:end-1,:),z(1:end-1,:), ...
    x(2:end,:),y(2:end,:),z(2:end,:),xLimits,yLimits,xTolerance,yTolerance)]; %#ok<AGROW>

% A rectangle can lie entirely inside one cell without containing any grid
% vertex or crossing any grid edge. Its four corners still define samples.
% Interpolate the two bounding rows at each y before locating the x interval;
% this respects Mollweide's narrowing footprint and does not clamp blank
% regions to the curved map edge.
for cornerY=yLimits
    for cornerX=xLimits
        value=cornerSample(x,y(:,1),z,cornerX,cornerY,xTolerance,yTolerance);
        samples=[samples; value(:)]; %#ok<AGROW>
    end
end
samples=samples(isfinite(samples));
if isempty(samples), return; end
limits=usableLimits([min(samples),max(samples)]);
info=struct('mode','local','limits',limits,'sampleCount',numel(samples));
end

function pair=orderedPair(pair,name)
validateattributes(pair,{'numeric'},{'real','finite','numel',2},mfilename,name);
pair=double(pair(:)');
if pair(2)<pair(1)
    error('gravity:ViewportLimits','%s must be in increasing order.',name);
end
end

function samples=edgeSamples(xa,ya,za,xb,yb,zb,xl,yl,xtol,ytol)
xa=xa(:); ya=ya(:); za=za(:); xb=xb(:); yb=yb(:); zb=zb(:);
candidate=isfinite(za)&isfinite(zb) & ...
    max(xa,xb)>=xl(1)-xtol & min(xa,xb)<=xl(2)+xtol & ...
    max(ya,yb)>=yl(1)-ytol & min(ya,yb)<=yl(2)+ytol;
xa=xa(candidate); ya=ya(candidate); za=za(candidate);
xb=xb(candidate); yb=yb(candidate); zb=zb(candidate);
samples=zeros(0,1);
dx=xb-xa; dy=yb-ya;
parameterTolerance=32*eps(1);
for boundary=xl
    valid=dx~=0;
    t=(boundary-xa(valid))./dx(valid);
    yy=ya(valid)+t.*dy(valid);
    keep=t>=-parameterTolerance & t<=1+parameterTolerance & ...
        yy>=yl(1)-ytol & yy<=yl(2)+ytol;
    t=min(1,max(0,t(keep)));
    aa=za(valid); bb=zb(valid);
    samples=[samples;(1-t).*aa(keep)+t.*bb(keep)]; %#ok<AGROW>
end
for boundary=yl
    valid=dy~=0;
    t=(boundary-ya(valid))./dy(valid);
    xx=xa(valid)+t.*dx(valid);
    keep=t>=-parameterTolerance & t<=1+parameterTolerance & ...
        xx>=xl(1)-xtol & xx<=xl(2)+xtol;
    t=min(1,max(0,t(keep)));
    aa=za(valid); bb=zb(valid);
    samples=[samples;(1-t).*aa(keep)+t.*bb(keep)]; %#ok<AGROW>
end
end

function value=cornerSample(x,rowY,z,cx,cy,xtol,ytol)
value=zeros(0,1);
if cy<rowY(1)-ytol || cy>rowY(end)+ytol, return; end
cy=min(rowY(end),max(rowY(1),cy));
lower=find(rowY<=cy,1,'last');
if isempty(lower), lower=1; end
if lower==numel(rowY) || abs(cy-rowY(lower))<=ytol
    rowX=x(lower,:); rowZ=z(lower,:);
else
    height=rowY(lower+1)-rowY(lower);
    if height<=0, return; end
    weight=(cy-rowY(lower))/height;
    rowX=(1-weight)*x(lower,:)+weight*x(lower+1,:);
    rowZ=(1-weight)*z(lower,:)+weight*z(lower+1,:);
end
if cx<rowX(1)-xtol || cx>rowX(end)+xtol, return; end
cx=min(rowX(end),max(rowX(1),cx));
atVertex=abs(rowX-cx)<=xtol;
if any(atVertex)
    % At an exactly/near collapsed pole, several columns share a coordinate.
    % Keeping their finite values avoids interp1's duplicate-x restriction.
    value=rowZ(atVertex & isfinite(rowZ));
    return
end
left=find(rowX<cx,1,'last');
if isempty(left) || left==numel(rowX), return; end
right=left+1;
width=rowX(right)-rowX(left);
if width<=0 || ~isfinite(rowZ(left)) || ~isfinite(rowZ(right)), return; end
weight=(cx-rowX(left))/width;
value=(1-weight)*rowZ(left)+weight*rowZ(right);
end

function limits=usableLimits(limits)
% Ordinary varying data retain their exact min/max. A few-ULP interval alone
% is expanded enough for distinct contour levels; real constant fields use
% a small relative padding (zero uses +/-1e-6).
if limits(1)==limits(2)
    center=limits(1);
    padding=1e-6*max(1,abs(center));
    limits=[center-padding,center+padding];
    if ~isfinite(limits(1)), limits(1)=center; end
    if ~isfinite(limits(2)), limits(2)=center; end
elseif limits(2)-limits(1)<64*eps(max(abs(limits)))
    padding=32*eps(max(abs(limits)));
    expanded=limits+[-padding,padding];
    finite=isfinite(expanded);
    limits(finite)=expanded(finite);
end
end
