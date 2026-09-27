function render_viewport_previews
%RENDER_VIEWPORT_PREVIEWS Compare the same real map with global/local scales.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(root);
out=fullfile(root,'artifacts');
if ~isfolder(out), mkdir(out); end
f=gravity_field_app('RenderQuality','fine');
cleanup=onCleanup(@()delete(f)); %#ok<NASGU>
setControl('FieldMode','centrifugal');
setControl('CentrifugalUnit','force');
setControl('CountrySearch','ECU');
tabs=findobj(f,'Tag','ProjectionTabs');
records=struct();
for projection={'miller','mollweide'}
    name=projection{1};
    tabs.SelectedTab=findobj(tabs,'Tag',name);
    feval(tabs.SelectionChangedFcn,tabs,struct());
    a=findobj(f,'Tag',['Axes_' name]);
    [x,y]=gravity_project([-82 -68 -82 -68],[-5 -5 5 5],name);
    a.XLim=[min(x) max(x)]; a.YLim=[min(y) max(y)];
    drawnow; pause(0.5); drawnow;
    if strcmp(name,'miller')
        setControl('LocalColorScale',false);
        records.globalLimits=a.CLim;
        exportapp(f,fullfile(out,'centrifugal_region_global_scale.png'));
        setControl('LocalColorScale',true);
        records.localLimits=a.CLim;
        records.local=getappdata(a,'ViewportColorStats');
        records.mass=f.UserData.mass;
        exportapp(f,fullfile(out,'centrifugal_region_local_scale.png'));
    else
        exportapp(f,fullfile(out,'centrifugal_region_mollweide_preview.png'));
    end
end
fid=fopen(fullfile(out,'viewport_colors.json'),'w','n','UTF-8');
fileCleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s\n',jsonencode(records,'PrettyPrint',true));

    function setControl(tag,value)
        item=findobj(f,'Tag',tag); item.Value=value;
        feval(item.ValueChangedFcn,item,struct());
        drawnow; pause(0.3); drawnow;
    end
end
