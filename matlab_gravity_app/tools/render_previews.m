function render_previews
%RENDER_PREVIEWS Export actual MATLAB UI captures for visual verification.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root);
out=fullfile(root,'artifacts');
if ~isfolder(out), mkdir(out); end
f=gravity_field_app;
cleanup=onCleanup(@()delete(f)); %#ok<NASGU>
tabs=findobj(f,'Tag','ProjectionTabs');
names={'globe','miller','equirectangular','mercator','mollweide'};
for k=1:numel(names)
    tabs.SelectedTab=findobj(tabs,'Tag',names{k});
    feval(tabs.SelectionChangedFcn,tabs,struct());
    drawnow; pause(1);
    exportapp(f,fullfile(out,[names{k} '_preview.png']));
end
tabs.SelectedTab=findobj(tabs,'Tag','globe');
mode=findobj(f,'Tag','FieldMode'); mode.Value='gravity';
feval(mode.ValueChangedFcn,mode,struct());
drawnow; pause(1); exportapp(f,fullfile(out,'total_gravity_preview.png'));
mode.Value='elevation';
feval(mode.ValueChangedFcn,mode,struct());
drawnow; pause(1); exportapp(f,fullfile(out,'elevation_preview.png'));
tabs.SelectedTab=findobj(tabs,'Tag','miller');
feval(tabs.SelectionChangedFcn,tabs,struct());
drawnow; pause(1); exportapp(f,fullfile(out,'elevation_miller_preview.png'));
tabs.SelectedTab=findobj(tabs,'Tag','globe');
mode.Value='centrifugal';
feval(mode.ValueChangedFcn,mode,struct());
drawnow; pause(1); exportapp(f,fullfile(out,'centrifugal_preview.png'));
units=findobj(f,'Tag','CentrifugalUnit'); units.Value='force';
feval(units.ValueChangedFcn,units,struct());
drawnow; pause(1); exportapp(f,fullfile(out,'centrifugal_force_preview.png'));
search=findobj(f,'Tag','CountrySearch'); search.Value='NRU';
feval(search.ValueChangedFcn,search,struct());
drawnow; pause(1); exportapp(f,fullfile(out,'coastal_capital_preview.png'));
end
