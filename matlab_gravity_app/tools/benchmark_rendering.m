function report = benchmark_rendering(varargin)
%BENCHMARK_RENDERING Reproducible, visible UI rendering performance check.
%   benchmark_rendering('Target','baseline') measures committed b8fdcb8.
%   benchmark_rendering('Target','optimized') measures current working code.
%   benchmark_rendering measures both, sequentially in one MATLAB process.
%   JSON results are written under artifacts/. Baseline code is obtained with
%   git show into ignored .cache/, renaming only its entry point and data root.
%   No production source or running MATLAB session is modified by this tool.
%   Run without another graphics benchmark or MATLAB test running in parallel.
%   Callback timings include synchronous callback work and a full drawnow.
%   Automated view changes measure redraw throughput, not mouse-interactive FPS.
parser=inputParser;
addParameter(parser,'Target','all');
addParameter(parser,'Repeats',5);
addParameter(parser,'StartupRepeats',3);
addParameter(parser,'RotationFrames',24);
addParameter(parser,'Qualities',{'balanced','fast','fine'});
addParameter(parser,'Position',[30 40 1510 880]);
parse(parser,varargin{:});
options=parser.Results;
assert(any(strcmp(options.Target,{'all','baseline','optimized'})),'Unknown target.');
assert(all(ismember(options.Qualities,{'balanced','fast','fine'})),'Unknown render quality.');
assert(options.Repeats>=3 && options.Repeats==fix(options.Repeats),'Use at least three repeats.');
assert(options.StartupRepeats>=1 && options.StartupRepeats==fix(options.StartupRepeats),'Invalid startup repeats.');
assert(options.RotationFrames>=4 && options.RotationFrames==fix(options.RotationFrames),'Use at least four frames.');
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root);
out=fullfile(root,'artifacts');
if ~isfolder(out), mkdir(out); end
report=struct('method',methodDescription(),'configuration',options,'environment',environmentInfo());
if any(strcmp(options.Target,{'all','baseline'}))
    baseline=prepareBaseline(root);
    addpath(fileparts(baseline));
    clear gravity_field_app_baseline;
    report.baseline=measureApp(@gravity_field_app_baseline,'baseline_b8fdcb8','',options);
    saveReport(fullfile(out,'rendering_baseline_benchmark.json'),report);
end
if any(strcmp(options.Target,{'all','optimized'}))
    clear gravity_field_app;
    for k=1:numel(options.Qualities)
        quality=options.Qualities{k};
        key=['optimized' upper(quality(1)) quality(2:end)];
        report.(key)=measureApp(@gravity_field_app,['optimized_' quality],quality,options);
        % Preserve finished profiles if a later profile fails or is interrupted.
        saveReport(fullfile(out,'rendering_optimized_benchmark.json'),report);
    end
end
if strcmp(options.Target,'all')
    saveReport(fullfile(out,'rendering_benchmark.json'),report);
end
end

function baseline=prepareBaseline(root)
cache=fullfile(root,'.cache');
if ~isfolder(cache), mkdir(cache); end
[code,source]=system(sprintf('git -C "%s" show b8fdcb8:matlab_gravity_app/gravity_field_app.m',root));
assert(code==0,'Cannot retrieve the committed b8fdcb8 baseline from local Git.');
source=strrep(source,'function fig = gravity_field_app(varargin)', ...
    'function fig = gravity_field_app_baseline(varargin)');
source=strrep(source,'root = fileparts(mfilename(''fullpath''));', ...
    'root = fileparts(fileparts(mfilename(''fullpath'')));');
assert(contains(source,'function fig = gravity_field_app_baseline(varargin)'), ...
    'Baseline signature changed unexpectedly.');
baseline=fullfile(cache,'gravity_field_app_baseline.m');
fid=fopen(baseline,'w','n','UTF-8');
assert(fid>=0,'Cannot create ignored baseline source.');
finish=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',source);
end

function result=measureApp(factory,name,quality,options)
fprintf('\nBENCHMARK START %s\n',name);
% One complete opening warms shared function loading and persistent model data.
warm=makeApp(factory,quality,options.Position);
delete(warm); drawnow;
startup=zeros(1,options.StartupRepeats);
for k=1:numel(startup)
    watch=tic;
    fig=makeApp(factory,quality,options.Position);
    startup(k)=toc(watch);
    if k<numel(startup), delete(fig); drawnow; end
end
finish=onCleanup(@()deleteValid(fig)); %#ok<NASGU>
result=struct('name',name,'quality',quality,'startupSeconds',summarize(startup));
fprintf('  Warm startup median %.3fs; collecting control samples...\n',median(startup));
result.globeScene=sceneCounts(fig,'globe');
% Exercise every measured control once before collecting steady-state samples.
setControl(fig,'Opacity',0.7); setControl(fig,'Opacity',0.78);
setControl(fig,'Relief',0.1); setControl(fig,'Relief',0.16);
setControl(fig,'FieldMode','gravity'); setControl(fig,'FieldMode','disturbance');
firstMap=tic; showTab(fig,'miller'); drawnow;
result.firstMillerTabSeconds=toc(firstMap);
result.millerScene=sceneCounts(fig,'miller');
showTab(fig,'globe'); drawnow;
result.opacity=measureControl(fig,'Opacity',[0.62 0.84 0.7 0.9 0.78],options.Repeats);
setControl(fig,'Opacity',0.78);
result.relief=measureControl(fig,'Relief',[0.10 0.22 0.12 0.18 0.16],options.Repeats);
setControl(fig,'Relief',0.16);
result.fieldSwitch=measureControl(fig,'FieldMode',{'gravity','disturbance'},options.Repeats);
setControl(fig,'FieldMode','disturbance');
result.returnToGlobe=measureTabReturn(fig,'miller','globe',options.Repeats);
result.returnToMiller=measureTabReturn(fig,'globe','miller',options.Repeats);
showTab(fig,'globe'); drawnow;
axesHandle=findobj(fig,'Tag','Axes_globe');
initialView=axesHandle.View;
for k=1:4
    axesHandle.View=initialView+[3*k 0]; drawnow;
end
frames=zeros(1,options.RotationFrames);
for k=1:numel(frames)
    watch=tic;
    axesHandle.View=initialView+[3*(k+4) 0]; drawnow;
    frames(k)=toc(watch);
end
axesHandle.View=initialView; drawnow;
result.automatedRotationFrameSeconds=summarize(frames);
result.automatedRotationRedrawsPerSecond=numel(frames)/sum(frames);
result.finalGlobeScene=sceneCounts(fig,'globe');
result.calculator=fig.UserData;
fprintf('BENCHMARK DONE %s startup %.3fs opacity %.3fs relief %.3fs field %.3fs globe return %.3fs redraw %.2f/s\n', ...
    name,median(startup),result.opacity.totalSeconds.median,result.relief.totalSeconds.median, ...
    result.fieldSwitch.totalSeconds.median,result.returnToGlobe.totalSeconds.median, ...
    result.automatedRotationRedrawsPerSecond);
end

function fig=makeApp(factory,quality,position)
if isempty(quality)
    fig=factory('Visible','on','Position',position);
else
    fig=factory('Visible','on','Position',position,'RenderQuality',quality);
    dropdown=findobj(fig,'Tag','RenderQuality');
    assert(isscalar(dropdown),'Optimized app must expose RenderQuality.');
    assert(strcmp(dropdown.Value,quality),'Requested quality was not applied at construction.');
end
drawnow;
end

function result=measureControl(fig,tag,values,n)
elapsed=zeros(n,2);
control=findobj(fig,'Tag',tag);
for k=1:n
    if iscell(values), value=values{1+mod(k-1,numel(values))};
    else, value=values(1+mod(k-1,numel(values))); end
    control.Value=value;
    watch=tic;
    invoke(control,'ValueChangedFcn');
    elapsed(k,1)=toc(watch);
    drawnow;
    elapsed(k,2)=toc(watch);
end
result=struct('callbackSeconds',summarize(elapsed(:,1)'), ...
    'totalSeconds',summarize(elapsed(:,2)'));
end

function result=measureTabReturn(fig,away,back,n)
elapsed=zeros(n,2);
tabs=findobj(fig,'Tag','ProjectionTabs');
for k=1:n
    showTab(fig,away); drawnow;
    watch=tic;
    tabs.SelectedTab=findobj(tabs,'Tag',back);
    invoke(tabs,'SelectionChangedFcn');
    elapsed(k,1)=toc(watch);
    drawnow;
    elapsed(k,2)=toc(watch);
end
result=struct('callbackSeconds',summarize(elapsed(:,1)'), ...
    'totalSeconds',summarize(elapsed(:,2)'));
end

function setControl(fig,tag,value)
control=findobj(fig,'Tag',tag);
control.Value=value; invoke(control,'ValueChangedFcn'); drawnow;
end

function showTab(fig,name)
tabs=findobj(fig,'Tag','ProjectionTabs');
tabs.SelectedTab=findobj(tabs,'Tag',name);
invoke(tabs,'SelectionChangedFcn');
end

function invoke(control,property)
callback=control.(property);
if isa(callback,'function_handle'), callback(control,[]);
elseif iscell(callback), callback{1}(control,[],callback{2:end});
else, error('Expected a callable control callback.'); end
end

function counts=sceneCounts(fig,name)
a=findobj(fig,'Tag',['Axes_' name]);
objects=findall(a);
counts=struct('axesObjectCount',numel(objects));
surface=findobj(a,'Tag','GravitySurface');
if ~isempty(surface)
    counts.gravitySurfaceGridSize=size(surface(1).XData);
    counts.gravitySurfaceVertices=numel(surface(1).XData);
    s=size(surface(1).XData);
    counts.gravitySurfaceTriangles=2*(s(1)-1)*(s(2)-1);
end
counts.surfaceObjectCount=numel(findobj(a,'Type','surface'));
allSurfaces=findobj(a,'Type','surface');
counts.totalSurfaceVertices=0;
counts.totalSurfaceTriangles=0;
for k=1:numel(allSurfaces)
    counts.totalSurfaceVertices=counts.totalSurfaceVertices+numel(allSurfaces(k).XData);
    s=size(allSurfaces(k).XData);
    counts.totalSurfaceTriangles=counts.totalSurfaceTriangles+2*max(0,s(1)-1)*max(0,s(2)-1);
end
boundaries=findobj(a,'Tag','CountryBoundaries');
counts.boundaryVertices=0;
for k=1:numel(boundaries)
    counts.boundaryVertices=counts.boundaryVertices+sum(isfinite(boundaries(k).XData(:)));
end
capitals=findobj(a,'Tag','CapitalMarkers');
counts.capitalCount=numel(capitals(1).XData);
contour=findobj(a,'Tag','GravityContours');
if ~isempty(contour) && isprop(contour(1),'XData')
    counts.contourCoordinateElements=numel(contour(1).XData);
end
end

function result=summarize(samples)
result=struct('samples',samples,'median',median(samples), ...
    'min',min(samples),'max',max(samples),'mean',mean(samples));
end

function result=environmentInfo()
result=struct('matlabVersion',version,'computer',computer, ...
    'timestamp',char(datetime('now','Format','yyyy-MM-dd HH:mm:ss')), ...
    'graphicsVisible',true,'processStartupIncluded',false);
try
    info=opengl('data');
    result.openglRenderer=info.Renderer;
    result.openglVersion=info.Version;
    result.openglSoftware=info.Software;
catch
    result.openglRenderer='not reported';
end
end

function text=methodDescription()
text=['Warm each app once, then open three visible figures sequentially for startup. ' ...
    'Only one app window is alive while sampling. Startup excludes MATLAB process launch. ' ...
    'Control tests use repeated real callbacks followed by a full drawnow; no screen capture ' ...
    'or disk I/O is timed. Tab return is measured after each tab has already been visited. ' ...
    'Programmatic camera angle changes plus drawnow measure redraw throughput; this is ' ...
    'not a mouse-input latency test or a guaranteed interactive frame rate. ' ...
    'The bundled gravity data and 197-country catalogue are shared by both versions.'];
end

function saveReport(path,report)
fid=fopen(path,'w','n','UTF-8');
assert(fid>=0,'Cannot write benchmark JSON.');
finish=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(report,'PrettyPrint',true));
fprintf('Saved %s\n',path);
end

function deleteValid(fig)
if isgraphics(fig), delete(fig); end
end
