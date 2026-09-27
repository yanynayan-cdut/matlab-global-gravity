function finalize_geodata
%FINALIZE_GEODATA Serialize Unicode country structs through native MATLAB.
root = fileparts(fileparts(mfilename('fullpath')));
target = fullfile(root,'data','world_geodata.mat');
geodata = load(target);
fid = fopen(fullfile(root,'data','countries_superset.json'),'r','n','UTF-8');
assert(fid >= 0,'Cannot read capital source JSON.');
cleanup = onCleanup(@() fclose(fid));
source = jsondecode(fscanf(fid,'%c'));
geodata.countries = reshape(source.countries,1,[]);
save(target,'-struct','geodata','-v7');
check = load(target);
assert(numel(check.countries) == 199);
assert(sum([check.countries.unMember]) == 193);
assert(nnz(ismember({check.countries.iso3},check.recommended197Iso3)) == 197);
fprintf('GEODATA_OK countries=%d recommended=%d boundaries=%d points=%d\n', ...
    numel(check.countries),numel(check.recommended197Iso3), ...
    numel(check.boundaries),nnz(isfinite(check.boundaryLatitude)));
end
