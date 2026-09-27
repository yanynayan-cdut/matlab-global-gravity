function [environment,cacheInfo] = load_surface_environment(varargin)
%LOAD_SURFACE_ENVIRONMENT Read measured terrain and persistent rotation cache.
%   [E,INFO] = load_surface_environment loads data/terrain_data.mat. Elevation
%   H is orthometric; E.hSurface = H + N is WGS84 ellipsoidal height. Ocean
%   cells retain their negative seabed elevation (OceanPolicy='seafloor').
%
%   E.acSurface and E.acHeightSlope give centrifugal acceleration in m/s^2:
%       ac = E.acSurface + E.acHeightSlope .* heightAboveSurfaceM
%   The same relation uses capitalAcSurface/capitalAcHeightSlope for the
%   independently sampled capitals; capitalHSurface is their H+N in m.
%   Multiply ac by the requested mass to get centrifugal force in N. This
%   quantity is already included in gravity_at_location's effective g.
%
%   Name/value options:
%     SourceFile   default: data/terrain_data.mat
%     CacheFile    default: data/centrifugal_cache.mat; if unwritable, use a
%                  user cache under prefdir. Explicit paths never fall back.
%     GeoidPolicy  'require' (default) or explicitly 'assume_zero'. In the
%                  latter case missing N remains NaN in original fields;
%                  geoidUsedM/capitalGeoidUsedM contain the declared zeros.
%     OceanPolicy  'seafloor' (negative elevations are never clipped to zero).
%
%   Cache identity includes the SHA-256 of the complete source file, WGS84
%   constants, algorithm/schema versions, and both height policies. Numeric
%   payload checksums and shape checks reject stale or corrupted disk caches.
%   Source SHA-256 is checked even for an in-memory hit. Only a verified
%   cache is reused; no missing source elevation is synthesized.
persistent memory
root=fileparts(mfilename('fullpath'));
parser=inputParser;
addParameter(parser,'SourceFile',fullfile(root,'data','terrain_data.mat'));
addParameter(parser,'CacheFile','');
addParameter(parser,'GeoidPolicy','require');
addParameter(parser,'OceanPolicy','seafloor');
parse(parser,varargin{:});
sourceFile=absolutePath(parser.Results.SourceFile);
explicitCache=~isempty(parser.Results.CacheFile);
if explicitCache
    candidates={absolutePath(parser.Results.CacheFile)};
else
    candidates={fullfile(root,'data','centrifugal_cache.mat'), ...
        fullfile(prefdir,'matlab-global-gravity','centrifugal_cache.mat')};
end
geoidPolicy=validatestring(parser.Results.GeoidPolicy,{'require','assume_zero'});
oceanPolicy=validatestring(parser.Results.OceanPolicy,{'seafloor'});
if ~isfile(sourceFile)
    error('GravityApp:MissingTerrainData','Missing measured terrain source: %s',sourceFile);
end
if ispc, sourceIsCache=any(strcmpi(sourceFile,candidates));
else, sourceIsCache=any(strcmp(sourceFile,candidates)); end
if sourceIsCache
    error('GravityApp:CachePath','CacheFile must differ from SourceFile.');
end
sourceSHA256=fileSHA256(sourceFile);
[~,reference]=centrifugal_at_location(0,0);
identity=struct('schemaVersion',1,'algorithmVersion','wgs84-centrifugal-surface-v1', ...
    'sourceSHA256',sourceSHA256,'constants',reference.constants, ...
    'heightPolicy','ellipsoidal h = orthometric H + geoid N', ...
    'geoidPolicy',geoidPolicy,'oceanPolicy',oceanPolicy);
memoryKey=struct('sourceFile',sourceFile,'candidates',{candidates},'identity',identity);
if ~isempty(memory) && isequal(memory.key,memoryKey) && isfile(memory.info.cacheFile)
    environment=memory.environment;
    cacheInfo=memory.info;
    cacheInfo.status='memory'; cacheInfo.recomputed=false; cacheInfo.written=false;
    return
end
environment=readTerrain(sourceFile,geoidPolicy);
% Reject a source replaced while it was being read rather than binding
% arrays from one source generation to another generation's fingerprint.
if ~strcmp(sourceSHA256,fileSHA256(sourceFile))
    error('GravityApp:TerrainChanged','Terrain source changed while reading it; retry loading.');
end
shape=size(environment.elevationM);
capitalCount=numel(environment.capitalIso3);
reasons=cell(1,numel(candidates));
record=[]; usedCache='';
for k=1:numel(candidates)
    [candidate,reasons{k}]=readCache(candidates{k},identity,shape,capitalCount);
    if ~isempty(candidate)
        record=candidate; usedCache=candidates{k}; break
    end
end
recomputed=isempty(record);
if recomputed
    gridLatitude=repmat(environment.lat,1,numel(environment.lon));
    [ac,detail]=centrifugal_at_location(gridLatitude,environment.hSurface);
    [capitalAc,capitalDetail]=centrifugal_at_location( ...
        environment.capitalLatitude,environment.capitalHSurface);
    payload=struct('acSurface',ac,'acHeightSlope',detail.heightSlope, ...
        'capitalAcSurface',capitalAc,'capitalAcHeightSlope',capitalDetail.heightSlope);
    record=struct('identity',identity,'payload',payload, ...
        'payloadSHA256',payloadSHA256(payload), ...
        'createdUTC',char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z''')));
    failures=cell(1,numel(candidates));
    for k=1:numel(candidates)
        try
            writeAtomic(candidates{k},record);
            usedCache=candidates{k};
            break
        catch exception
            failures{k}=exception.message;
        end
    end
    if isempty(usedCache)
        error('GravityApp:CacheWrite','Unable to persist centrifugal cache: %s', ...
            strjoin(failures(~cellfun('isempty',failures)),' | '));
    end
end
fields=fieldnames(record.payload);
for k=1:numel(fields), environment.(fields{k})=record.payload.(fields{k}); end
environment.constants=identity.constants;
environment.sourceSHA256=sourceSHA256;
environment.heightPolicy=identity.heightPolicy;
environment.geoidPolicy=geoidPolicy;
environment.oceanPolicy=oceanPolicy;
environment.centrifugalAccelerationUnit='m/s^2';
environment.centrifugalHeightSlopeUnit='s^-2';
environment.centrifugalAlreadyIncludedInEffectiveGravity=true;
if recomputed, status='computed'; else, status='disk'; end
cacheInfo=struct('status',status,'recomputed',recomputed,'written',recomputed, ...
    'cacheFile',usedCache,'sourceFile',sourceFile,'sourceSHA256',sourceSHA256, ...
    'schemaVersion',identity.schemaVersion,'algorithmVersion',identity.algorithmVersion, ...
    'geoidApproximationApplied',environment.approximation.applied, ...
    'rejectionReasons',{reasons});
memory=struct('key',memoryKey,'environment',environment,'info',cacheInfo);
end

function environment=readTerrain(path,geoidPolicy)
environment=load(path);
required={'lat','lon','elevationM','capitalIso3','capitalLatitude', ...
    'capitalLongitude','capitalElevationM'};
if ~all(isfield(environment,required))
    error('GravityApp:TerrainFields','Terrain source is missing required fields; no elevation fallback is allowed.');
end
requireFinite(environment.lat,'lat'); requireFinite(environment.lon,'lon');
lat=double(environment.lat(:)); lon=double(environment.lon(:)');
if ~isvector(environment.lat) || ~isvector(environment.lon) ...
        || numel(lat)<2 || numel(lon)<2 || any(diff(lat)<=0) || any(diff(lon)<=0) ...
        || any(abs(lat)>90) || any(abs(lon)>180)
    error('GravityApp:TerrainCoordinates','Terrain coordinates must be ascending latitude/longitude vectors in degrees.');
end
requireFinite(environment.elevationM,'elevationM');
H=double(environment.elevationM);
if ~isequal(size(H),[numel(lat),numel(lon)])
    error('GravityApp:TerrainShape','elevationM must be latitude-by-longitude.');
end
codes=normalizeCodes(environment.capitalIso3);
n=numel(codes);
if n~=197 || numel(unique(codes))~=197 ...
        || any(cellfun(@(c)isempty(regexp(c,'^[A-Z]{3}$','once')),codes))
    error('GravityApp:TerrainCapitals','Terrain source must contain 197 distinct ISO3 capital records.');
end
capitalFields={'capitalLatitude','capitalLongitude','capitalElevationM'};
for k=1:numel(capitalFields)
    name=capitalFields{k}; requireFinite(environment.(name),name);
    if numel(environment.(name))~=n
        error('GravityApp:TerrainCapitalShape','%s must contain one value per capital.',name);
    end
    environment.(name)=double(environment.(name)(:));
end
if any(abs(environment.capitalLatitude)>90) || any(abs(environment.capitalLongitude)>180)
    error('GravityApp:TerrainCapitalCoordinates','Invalid capital latitude/longitude.');
end
[N,usedN,approxGrid]=readGeoid(environment,'geoidUndulationM',size(H),geoidPolicy);
[capitalN,usedCapitalN,approxCapitals]=readGeoid(environment,'capitalGeoidM',[n 1],geoidPolicy);
environment.lat=lat; environment.lon=lon; environment.elevationM=H;
environment.capitalIso3=codes;
environment.geoidUndulationM=N; environment.capitalGeoidM=capitalN;
environment.geoidUsedM=usedN; environment.capitalGeoidUsedM=usedCapitalN;
environment.hSurface=H+usedN;
% Nearby land heights are estimates of H at the canonical capital. Keep its
% latitude, longitude and locally sampled geoid N for the force calculation.
environment.capitalHSurface=environment.capitalElevationM+usedCapitalN;
environment.approximation=struct('applied',any(approxGrid(:))||any(approxCapitals(:)), ...
    'policy',geoidPolicy,'gridMask',approxGrid,'capitalMask',approxCapitals);
end

function [raw,used,approximation]=readGeoid(environment,name,shape,policy)
if ~isfield(environment,name)
    raw=nan(shape);
else
    raw=environment.(name);
    if ~isnumeric(raw) || ~isreal(raw) || any(isinf(raw(:)))
        error('GravityApp:TerrainGeoid','%s must contain real geoid values or declared missing NaNs.',name);
    end
    if strcmp(name,'capitalGeoidM') && numel(raw)==prod(shape), raw=raw(:); end
    if ~isequal(size(raw),shape)
        error('GravityApp:TerrainGeoidShape','%s has incompatible dimensions.',name);
    end
    raw=double(raw);
end
approximation=isnan(raw);
if any(approximation(:)) && strcmp(policy,'require')
    error('GravityApp:MissingGeoid','%s is missing values. Supply measured N or explicitly choose GeoidPolicy=assume_zero.',name);
end
used=raw;
if strcmp(policy,'assume_zero'), used(approximation)=0; end
end

function codes=normalizeCodes(value)
if ischar(value) || isstring(value)
    codes=cellstr(value);
elseif iscell(value) && all(cellfun(@ischar,value(:)))
    codes=value;
else
    error('GravityApp:TerrainCapitals','capitalIso3 must contain ISO3 text codes.');
end
codes=cellfun(@(c)upper(strtrim(c)),codes(:),'UniformOutput',false);
end

function requireFinite(value,name)
if ~isnumeric(value) || ~isreal(value) || isempty(value) || any(~isfinite(value(:)))
    error('GravityApp:TerrainValues','%s must contain finite real measured values.',name);
end
end

function [record,reason]=readCache(path,identity,shape,capitalCount)
record=[];
if ~isfile(path), reason='missing'; return; end
try
    loaded=load(path,'record');
    assert(isfield(loaded,'record') && isstruct(loaded.record) && isscalar(loaded.record),'Missing cache record.');
    value=loaded.record;
    assert(all(isfield(value,{'identity','payload','payloadSHA256'})),'Missing cache metadata.');
    assert(isequal(value.identity,identity),'Cache source, model, or policy has changed.');
    names={'acSurface','acHeightSlope','capitalAcSurface','capitalAcHeightSlope'};
    assert(isstruct(value.payload) && isscalar(value.payload) ...
        && isequal(sort(fieldnames(value.payload)),sort(names(:))),'Missing or unexpected cache arrays.');
    for k=1:numel(names)
        array=value.payload.(names{k});
        if k<=2, expected=shape; else, expected=[capitalCount 1]; end
        assert(isa(array,'double') && isreal(array) && isequal(size(array),expected) ...
            && all(isfinite(array(:))) && all(array(:)>=0),'Invalid cached array dimensions or values.');
    end
    assert(ischar(value.payloadSHA256) && strcmp(value.payloadSHA256,payloadSHA256(value.payload)), ...
        'Cache payload checksum mismatch.');
    % Physical ranges additionally reject structurally valid nonsensical data.
    assert(all(value.payload.acHeightSlope(:)<=identity.constants.omegaRadPerSecond^2*(1+1e-12)) ...
        && all(value.payload.capitalAcHeightSlope(:)<=identity.constants.omegaRadPerSecond^2*(1+1e-12)), ...
        'Invalid cached centrifugal height slope.');
    record=value; reason='valid';
catch exception
    reason=exception.message;
end
end

function digest=payloadSHA256(payload)
engine=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
names={'acSurface','acHeightSlope','capitalAcSurface','capitalAcHeightSlope'};
for k=1:numel(names)
    value=payload.(names{k});
    header=unicode2native(sprintf('%s|double|%dx%d|',names{k},size(value,1),size(value,2)),'UTF-8');
    engine.update(typecast(uint8(header(:)),'int8'));
    % Canonical little-endian binary doubles make the checksum portable.
    [~,~,endian]=computer;
    if endian=='B', value=swapbytes(value); end
    engine.update(typecast(value(:),'int8'));
end
digest=lower(reshape(dec2hex(typecast(engine.digest(),'uint8'),2).',1,[]));
end

function digest=fileSHA256(path)
fid=fopen(path,'rb');
if fid<0, error('GravityApp:TerrainRead','Cannot read %s.',path); end
finish=onCleanup(@()fclose(fid)); %#ok<NASGU>
engine=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
if fseek(fid,0,'eof')~=0
    error('GravityApp:TerrainRead','Cannot determine size of %s.',path);
end
expectedBytes=ftell(fid);
if expectedBytes<0 || fseek(fid,0,'bof')~=0
    error('GravityApp:TerrainRead','Cannot seek in %s.',path);
end
readBytes=0;
while readBytes<expectedBytes
    request=min(1024*1024,expectedBytes-readBytes);
    chunk=fread(fid,request,'*uint8');
    if isempty(chunk)
        error('GravityApp:TerrainRead','Unexpected end of %s.',path);
    end
    readBytes=readBytes+numel(chunk);
    engine.update(typecast(chunk(:),'int8'));
end
if readBytes~=expectedBytes
    error('GravityApp:TerrainRead','Incomplete read of %s.',path);
end
digest=lower(reshape(dec2hex(typecast(engine.digest(),'uint8'),2).',1,[]));
end

function writeAtomic(path,record)
folder=fileparts(path);
if ~isfolder(folder)
    [ok,message]=mkdir(folder);
    if ~ok, error('GravityApp:CacheDirectory','%s',message); end
end
temporary=[tempname(folder) '.mat'];
finish=onCleanup(@()deleteTemporary(temporary)); %#ok<NASGU>
save(temporary,'record','-v7');
% Both files are on the same filesystem. Require an atomic rename, leaving
% any previous cache intact if the filesystem does not support that operation.
source=javaObject('java.io.File',temporary);
target=javaObject('java.io.File',path);
options=javaArray('java.nio.file.CopyOption',2);
options(1)=javaMethod('valueOf','java.nio.file.StandardCopyOption','ATOMIC_MOVE');
options(2)=javaMethod('valueOf','java.nio.file.StandardCopyOption','REPLACE_EXISTING');
javaMethod('move','java.nio.file.Files',source.toPath(),target.toPath(),options);
end

function deleteTemporary(path)
if isfile(path), delete(path); end
end

function path=absolutePath(value)
if ~(ischar(value) && isrow(value) || isstring(value) && isscalar(value)) || strlength(string(value))==0
    error('GravityApp:TerrainPath','File paths must be nonempty scalar text.');
end
file=javaObject('java.io.File',char(value));
if ~file.isAbsolute(), file=javaObject('java.io.File',fullfile(pwd,char(value))); end
path=char(file.getCanonicalPath());
end
