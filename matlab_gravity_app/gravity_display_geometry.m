function out = gravity_display_geometry(lat,lon,values,boundaryLat,boundaryLon,quality)
%GRAVITY_DISPLAY_GEOMETRY Display-only sampling and topology-aware line LOD.
% Scientific input arrays are not modified. The calculator uses the original
% spherical-harmonic model independently of these visualization arrays.
quality=validatestring(quality,{'fast','balanced','fine'});
lat=double(lat(:)); lon=double(lon(:)');
assert(isequal(size(values),[numel(lat),numel(lon)]),'gravity:GridSize','Grid size mismatch.');
assert(all(diff(lat)>0)&&all(diff(lon)>0),'gravity:GridOrder','Grid axes must increase.');
switch quality
    case 'fast', stride=4; tolerance=0.20; maxStep=2;
    case 'balanced', stride=2; tolerance=0.07; maxStep=1;
    otherwise, stride=1; tolerance=0; maxStep=0.5;
end
% Keep Mercator's clipping latitudes even in the coarser display grids.
rows=unique([1:stride:numel(lat),numel(lat),find(abs(abs(lat)-85)<1e-10)']);
cols=unique([1:stride:numel(lon),numel(lon)]);
out=struct('lat',lat(rows),'lon',lon(cols),'values',values(rows,cols), ...
    'rowIndex',rows,'columnIndex',cols,'quality',quality,'stride',stride);
bl=double(boundaryLat(:)); bo=double(boundaryLon(:));
assert(numel(bl)==numel(bo),'gravity:BoundarySize','Boundary dimensions differ.');
valid=isfinite(bl)&isfinite(bo);
edges=diff([false;valid;false]); starts=find(edges==1); stops=find(edges==-1)-1;
parts=cell(numel(starts),1); partCount=0;
for k=1:numel(starts)
    p=[bo(starts(k):stops(k)),bl(starts(k):stops(k))];
    % Preserve both endpoints on either side of a longitude branch cut.
    splits=[1;find(abs(diff(p(:,1)))>180)+1;size(p,1)+1];
    for j=1:numel(splits)-1
        segment=p(splits(j):splits(j+1)-1,:);
        if tolerance>0 && size(segment,1)>8
            closed=norm(segment(1,:)-segment(end,:))<1e-10;
            indices=rdpIndices(segment,tolerance);
            if ~closed || numel(indices)>=4
                segment=segment(indices,:);
            end
            segment=densify(segment,maxStep);
        end
        partCount=partCount+1;
        parts{partCount}=[segment;NaN NaN];
    end
end
if partCount>0, lines=vertcat(parts{1:partCount}); else, lines=zeros(0,2); end
out.boundaryLongitude=lines(:,1); out.boundaryLatitude=lines(:,2);
out.metadata=struct('sourceGridVertices',numel(values),'displayGridVertices',numel(out.values), ...
    'sourceBoundaryVertices',nnz(valid),'displayBoundaryVertices',nnz(isfinite(lines(:,1))), ...
    'componentCount',partCount,'toleranceDegrees',tolerance,'maxSegmentDegrees',maxStep);
end

function keep=rdpIndices(points,tolerance)
% Ramer-Douglas-Peucker in a locally scaled longitude/latitude plane.
work=points;
work(:,1)=work(:,1)*max(cosd(mean(work(:,2))),0.05);
n=size(work,1); selected=false(n,1); selected([1 n])=true;
stack=zeros(n,2); stack(1,:)=[1 n]; top=1;
while top>0
    ends=stack(top,:); top=top-1;
    first=ends(1); last=ends(2);
    if last<=first+1, continue; end
    offset=work(first+1:last-1,:)-work(first,:);
    v=work(last,:)-work(first,:); norm2=sum(v.^2);
    if norm2==0
        distance2=sum(offset.^2,2);
    else
        t=max(0,min(1,(offset*v')/norm2));
        distance2=sum((offset-t.*v).^2,2);
    end
    [largest,at]=max(distance2);
    if largest>tolerance^2
        at=at+first; selected(at)=true;
        stack(top+1,:)=[first at]; stack(top+2,:)=[at last]; top=top+2;
    end
end
keep=find(selected);
end

function result=densify(points,maxStep)
% Long chords must still follow the curved/radially displaced sphere.
if size(points,1)<2, result=points; return; end
steps=max(1,ceil(max(abs(diff(points,1,1)),[],2)/maxStep));
result=zeros(sum(steps)+1,2); position=1;
for k=1:numel(steps)
    t=(0:steps(k)-1)'/steps(k);
    rows=position:position+steps(k)-1;
    result(rows,:)=points(k,:)+t.*(points(k+1,:)-points(k,:));
    position=position+steps(k);
end
result(end,:)=points(end,:);
end
