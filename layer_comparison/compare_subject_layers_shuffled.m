function compare_subject_layers_shuffled(subj_info, contrast, shuff_idx, varargin)

% Parse inputs
defaults = struct('data_dir', 'd:/pred_coding/derivatives/spm12', 'save_results', true,...
    'inv_type','EBB','patch_size', 5.0, 'surf_dir','D:/pred_coding/derivatives/freesurfer', 'filter_sessions', true);  %define default values
params = struct(varargin{:});
for f = fieldnames(defaults)',
    if ~isfield(params, f{1}),
        params.(f{1}) = defaults.(f{1});
    end
end

% Get map from white matter to pial surface
orig_white_mesh=fullfile(params.surf_dir,subj_info.subj_id,'white.hires.deformed.surf.gii');
white_mesh=fullfile(params.surf_dir,subj_info.subj_id,'ds_white.hires.deformed.surf.gii');
orig_pial_mesh=fullfile(params.surf_dir,subj_info.subj_id,'pial.hires.deformed.surf.gii');
pial_mesh=fullfile(params.surf_dir,subj_info.subj_id,'ds_pial.hires.deformed.surf.gii');

pial_white_map=map_pial_to_white(white_mesh, pial_mesh, 'mapType', 'link',...
    'origPial', orig_pial_mesh, 'origWhite', orig_white_mesh);

nvertices=length(pial_white_map);

pial_diff=[];
white_diff=[];

for session_num=1:length(subj_info.sessions)
    foi_dir=fullfile(params.data_dir, subj_info.subj_id,...
        sprintf('ses-0%d',session_num), 'grey_coreg', params.inv_type,...
        ['p' num2str(params.patch_size)], contrast.zero_event,...
        ['f' num2str(contrast.foi(1)) '_' num2str(contrast.foi(2))],...
        'shuffled', num2str(shuff_idx));

    session_pial_diff=gifti(fullfile(foi_dir, sprintf('pial.%s.diff.gii', contrast.comparison_name)));
    ntrials=size(session_pial_diff.cdata,2);
    pial_diff(:,end+1:end+ntrials)=session_pial_diff.cdata(:,:);
    
    session_white_diff=gifti(fullfile(foi_dir, sprintf('white.%s.diff.gii', contrast.comparison_name)));
    ntrials=size(session_white_diff.cdata,2);
    white_diff(:,end+1:end+ntrials)=session_white_diff.cdata(:,:);
end


foi_dir=fullfile(params.data_dir, subj_info.subj_id,...
    'grey_coreg', params.inv_type, ['p' num2str(params.patch_size)],...
    contrast.zero_event, ['f' num2str(contrast.foi(1)) '_' num2str(contrast.foi(2))],...
    'shuffled', num2str(shuff_idx));
mkdir(foi_dir);

% Save pial/wm diff
write_metric_gifti(fullfile(foi_dir, ['pial.' contrast.comparison_name '.diff.dat']), pial_diff);
write_metric_gifti(fullfile(foi_dir, ['white.' contrast.comparison_name '.diff.dat']), white_diff);

% Compare pial values at two wois
[H,pvals,ci,STATS]=ttest(pial_diff');
pial_tvals=STATS.tstat';

% Save pial comparison
write_metric_gifti(fullfile(foi_dir, ['pial.' contrast.comparison_name '.t.dat']), pial_tvals);

% Compare white matter values at two wois
[H,pvals,ci,STATS]=ttest(white_diff');
white_tvals=STATS.tstat';

% Save white matter comparison
write_metric_gifti(fullfile(foi_dir, ['white.' contrast.comparison_name '.t.dat']), white_tvals);        

% Compare pial and white matter differences
pial_white_diff=abs(pial_diff)-abs(white_diff(pial_white_map,:));
[H,pvals,ci,STATS]=ttest(pial_white_diff');
pial_white_tvals=STATS.tstat';

% Save pial - white matter diff
write_metric_gifti(fullfile(foi_dir, ['pial-white.' contrast.comparison_name '.diff.dat']), pial_white_diff);        
write_metric_gifti(fullfile(foi_dir, ['pial-white.' contrast.comparison_name '.t.dat']), pial_white_tvals);        


