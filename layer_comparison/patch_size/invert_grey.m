function invert_grey(subj_info, session_num, contrast, varargin)

% Parse inputs
defaults = struct('data_dir', '/data/meg_laminar/derivatives/spm12', 'inv_type', 'EBB',...
    'patch_size',5, 'surf_dir', '/data/meg_laminar/derivatives/freesurfer',...
    'mri_dir', '/data/meg_laminar', 'init', true,...
    'coreg', true, 'invert', true);  %define default values
params = struct(varargin{:});
for f = fieldnames(defaults)',
    if ~isfield(params, f{1}),
        params.(f{1}) = defaults.(f{1});
    end
end

data_dir=fullfile(params.data_dir, subj_info.subj_id, sprintf('ses-%02d',session_num));
data_file_name=fullfile(data_dir, sprintf('rc%s_Tafdf%d.mat', contrast.zero_event, session_num));

% Create directory for inversion results
foi_dir=fullfile(data_dir, 'grey_coreg', params.inv_type, ['p' num2str(params.patch_size)], contrast.zero_event, ['f' num2str(contrast.foi(1)) '_' num2str(contrast.foi(2))]);
if exist(foi_dir,'dir')~=7
    mkdir(foi_dir);
end
coreg_file_name=fullfile(foi_dir, sprintf('%s_%d.mat', subj_info.subj_id, session_num));
removed_file_name=fullfile(foi_dir, sprintf('r%s_%d.mat', subj_info.subj_id, session_num));
bc_file_name=fullfile(foi_dir, sprintf('br%s_%d.mat', subj_info.subj_id, session_num));

spm('defaults', 'EEG');
spm_jobman('initcfg'); 

% Use all available spatial modes
ideal_Nmodes=[];
% Number of cross validation folds
Nfolds=1;
% Percentage of test channels in cross validation
ideal_pctest=0;

if params.init
    % Copy file to foi_dir
    clear jobs
    matlabbatch={};
    batch_idx=1;
    matlabbatch{batch_idx}.spm.meeg.other.copy.D = {data_file_name};
    matlabbatch{batch_idx}.spm.meeg.other.copy.outfile = coreg_file_name;
    batch_idx=batch_idx+1;

    % Remove bad trials
    matlabbatch{batch_idx}.spm.meeg.preproc.remove.D = {coreg_file_name};
    matlabbatch{batch_idx}.spm.meeg.preproc.remove.prefix = 'r';
    batch_idx=batch_idx+1;

    % Set EEG channels to other
    matlabbatch{batch_idx}.spm.meeg.preproc.prepare.D = {removed_file_name};
    matlabbatch{batch_idx}.spm.meeg.preproc.prepare.task{1}.settype.channels{1}.type = 'EEG';
    matlabbatch{batch_idx}.spm.meeg.preproc.prepare.task{1}.settype.newtype = 'Other';
    batch_idx=batch_idx+1;

    %%%%%% BASELINE CORRECT %%%%%%%%
    matlabbatch{batch_idx}.spm.meeg.preproc.bc.D = {removed_file_name};
    matlabbatch{batch_idx}.spm.meeg.preproc.bc.timewin = contrast.baseline_woi;
    matlabbatch{batch_idx}.spm.meeg.preproc.bc.prefix = 'b';
    
    spm_jobman('run', matlabbatch);

    % Relabel trials to all be same condition
    load(bc_file_name);
    D.condlist={contrast.zero_event};
    for trial_idx=1:length(D.trials)
        D.trials(trial_idx).label=contrast.zero_event;
    end
    save(bc_file_name,'D');
    
end

if params.coreg
    spm_jobman('initcfg'); 
    clear jobs
    matlabbatch={};
    batch_idx=1;

    % Coregister with surface
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.D = {bc_file_name};
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.val = 1;
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.comment = 'grey';
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.meshing.meshes.custom.mri = {fullfile(params.mri_dir,subj_info.subj_id,'anat',[subj_info.headcast_t1 ',1'])};
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.meshing.meshes.custom.cortex = {fullfile(params.surf_dir,subj_info.subj_id,'ds_white.hires.deformed-ds_pial.hires.deformed.surf.gii')};
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.meshing.meshes.custom.iskull = {''};
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.meshing.meshes.custom.oskull = {''};
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.meshing.meshes.custom.scalp = {''};
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.meshing.meshres = 2;
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.coregistration.coregspecify.fiducial(1).fidname = 'nas';
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.coregistration.coregspecify.fiducial(1).specification.type = subj_info.nas;
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.coregistration.coregspecify.fiducial(2).fidname = 'lpa';
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.coregistration.coregspecify.fiducial(2).specification.type = subj_info.lpa;
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.coregistration.coregspecify.fiducial(3).fidname = 'rpa';
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.coregistration.coregspecify.fiducial(3).specification.type = subj_info.rpa;
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.coregistration.coregspecify.useheadshape = 0;
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.forward.eeg = 'EEG BEM';
    matlabbatch{batch_idx}.spm.meeg.source.headmodel.forward.meg = 'Single Shell';
    spm_jobman('run',matlabbatch);
end

if params.invert
    spatialmodesname=fullfile(foi_dir, 'Umodes.mat');
    [spatialmodesname,Nmodes,pctest]=spm_eeg_inv_prep_modes_xval(bc_file_name,...
        ideal_Nmodes, spatialmodesname, Nfolds, ideal_pctest);

    % Run the inversion
    spm_jobman('initcfg'); 
    clear jobs
    matlabbatch={};
    batch_idx=1;
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.D = {bc_file_name};
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.val = 1;
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.whatconditions.all = 1;
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.invfunc = 'Classic';
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.invtype = params.inv_type;
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.woi = contrast.invwoi;
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.foi = contrast.foi;
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.hanning = 0;
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.isfixedpatch.randpatch.npatches = 512;
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.isfixedpatch.randpatch.niter = 1;
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.patchfwhm =[-params.patch_size]; %% NB A fiddle here- need to properly quantify
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.mselect = 0;
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.nsmodes = Nmodes;
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.umodes = {spatialmodesname};
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.ntmodes = 16;
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.priors.priorsmask = {''};
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.priors.space = 1;
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.restrict.locs = zeros(0, 3);
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.restrict.radius = 32;
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.isstandard.custom.outinv = '';
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.modality = {'MEG'};
    matlabbatch{batch_idx}.spm.meeg.source.invertiter.crossval = [pctest Nfolds];   
    spm_jobman('run',matlabbatch);
               
end
