function cond_results=plot_subject_condition_power(subj_info, contrast, varargin)

% Parse inputs
defaults = struct('data_dir','d:/meg_laminar/derivatives/spm12',...
    'surf_dir', 'D:/meg_laminar/derivatives/freesurfer',...
    'inv_type','EBB', 'patch_size',0.4,'thresh_percentile',80,...
    'roi_type','mean', 'recompute', false, 'recompute_roi',false,...
    'correct_only', true,'plot', true);  %define default values
params = struct(varargin{:});
for f = fieldnames(defaults)',
    if ~isfield(params, f{1}),
        params.(f{1}) = defaults.(f{1});
    end
end

spm('defaults','eeg');

% Split trials by condition
conditions={'congruent - low','congruent - med','congruent - high','incongruent - low','incongruent - med','incongruent - high'};
coherence_conditions={'low','med','high'};
congruence_conditions={'congruent','incongruent'};
accuracy_conditions={'correct', 'incorrect'};

cond_results.pial_trials_tc=dict();
cond_results.wm_trials_tc=dict();
cond_results.pial_trials_woi=dict();
cond_results.wm_trials_woi=dict();
cond_results.rts=dict();

for session_num=1:length(subj_info.sessions)
    
    [pial_roi_trials,wm_roi_trials,pial_roi_bc_trials,wm_roi_bc_trials,times,freqs]=compute_condition_power(subj_info,...
        session_num, contrast, 'data_dir',params.data_dir, 'surf_dir', params.surf_dir,...
        'inv_type', params.inv_type, 'patch_size', params.patch_size,...
        'thresh_percentile', params.thresh_percentile,'roi_type',params.roi_type,...
        'recompute', params.recompute,'recompute_roi', params.recompute_roi);

    freq_idx=intersect(find(freqs>=contrast.foi(1)),find(freqs<=contrast.foi(2)));
    time_idx=intersect(find(times>=contrast.baseline_woi(1)),find(times<=contrast.comparison_woi(2)));
    baseline_idx=intersect(find(times>=contrast.baseline_woi(1)),find(times<=contrast.baseline_woi(2)));
    woi_idx=intersect(find(times>=contrast.comparison_woi(1)),find(times<=contrast.comparison_woi(2)));
    
    pial_baseline=repmat(squeeze(mean(mean(pial_roi_trials(:,baseline_idx,:),3),2)),[1 length(times) size(pial_roi_trials,3)]);
    wm_baseline=repmat(squeeze(mean(mean(wm_roi_trials(:,baseline_idx,:),3),2)),[1 length(times) size(wm_roi_trials,3)]);
    
    pial_roi_bc_trials = (pial_roi_trials - pial_baseline)./pial_baseline.*100;
    wm_roi_bc_trials = (wm_roi_trials - wm_baseline)./wm_baseline.*100;
    
    pial_roi_bc_foi_trials=squeeze(mean(pial_roi_bc_trials(freq_idx,:,:),1));
    wm_roi_bc_foi_trials=squeeze(mean(wm_roi_bc_trials(freq_idx,:,:),1));
    
    pial_roi_bc_foi_trials_woi=squeeze(mean(pial_roi_bc_foi_trials(woi_idx,:),1));
    wm_roi_bc_foi_trials_woi=squeeze(mean(wm_roi_bc_foi_trials(woi_idx,:),1));
    
    pial_roi_bc_foi_trials_tc=pial_roi_bc_foi_trials(time_idx,:);
    wm_roi_bc_foi_trials_tc=wm_roi_bc_foi_trials(time_idx,:);
    
    % Load behavior files
    session_responses=[];
    for run_idx=1:subj_info.sessions(session_num)
        load(fullfile('C:/pred_coding/', subj_info.subj_id, sprintf('ses-0%d',session_num), 'behavior', sprintf('data_%d.mat', run_idx)));
        load(fullfile('C:/pred_coding/', subj_info.subj_id, sprintf('ses-0%d',session_num), 'behavior', sprintf('stim_%d.mat', run_idx)));
        
        % Remove no responses
        resp_idx=find(data.responses(:,1)~=0);
        data.responses=data.responses(resp_idx,:);
        stim.trials=stim.trials(resp_idx,:);
        % Flip
        data.responses(:,1)=2-data.responses(:,1)+1;
        % correct
        correct=data.responses(:,1)==stim.trials(:,4);
        session_responses(end+1:end+size(correct,1),:)=[correct data.responses(:,2)];
    end
    
    % Load coreg file - has condition labels
    data_dir=fullfile(params.data_dir, subj_info.subj_id, sprintf('ses-0%d',session_num));
    data_file_name=fullfile(data_dir, sprintf('rc%s_Tafdf%d.mat', contrast.zero_event, session_num));
    foi_dir=fullfile(data_dir, 'grey_coreg', params.inv_type, ['p' num2str(params.patch_size)],...
        contrast.zero_event, ['f' num2str(contrast.foi(1)) '_' num2str(contrast.foi(2))]);
    coreg_file_name=fullfile(foi_dir, sprintf('%s_%d.mat', subj_info.subj_id, session_num));
    removed_file_name=fullfile(foi_dir, sprintf('r%s_%d.mat', subj_info.subj_id, session_num));
    
    if exist(removed_file_name, 'file')~=2
        spm_jobman('initcfg'); 

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
        
        % Remove prefiltered files
        matlabbatch{batch_idx}.spm.meeg.other.delete.D = {coreg_file_name};
        batch_idx=batch_idx+1;
        spm_jobman('run',matlabbatch);
    end
    
    Dorig=spm_eeg_load(data_file_name);
    
    % Remove bad trials from behavioural data
    session_responses=session_responses(setdiff([1:size(session_responses,1)],Dorig.badtrials),:);
    
    % Remove bad trials from condition dataset
    Dremoved=spm_eeg_load(removed_file_name);
    
    correct_trials=find(session_responses(:,1)==1);
    incorrect_trials=find(session_responses(:,1)==0);

    cond_results.rts('correct')=session_responses(correct_trials,2);
    cond_results.rts('incorrect')=session_responses(incorrect_trials,2);
    
    cond_results.pial_trials_tc('correct')=pial_roi_bc_foi_trials_tc(:,correct_trials);               
    cond_results.pial_trials_tc('incorrect')=pial_roi_bc_foi_trials_tc(:,incorrect_trials);               
    cond_results.wm_trials_tc('correct')=wm_roi_bc_foi_trials_tc(:,correct_trials);               
    cond_results.wm_trials_tc('incorrect')=wm_roi_bc_foi_trials_tc(:,incorrect_trials);               
    
    cond_results.pial_trials_woi('correct')=pial_roi_bc_foi_trials_woi(correct_trials);
    cond_results.pial_trials_woi('incorrect')=pial_roi_bc_foi_trials_woi(incorrect_trials);
    cond_results.wm_trials_woi('correct')=wm_roi_bc_foi_trials_woi(correct_trials);
    cond_results.wm_trials_woi('incorrect')=wm_roi_bc_foi_trials_woi(incorrect_trials);
    
    % For each coherence condition
    for coher_cond_idx=1:length(coherence_conditions)

        % Get trials in this condition - congruent and incongruent
        coherence_condition=coherence_conditions{coher_cond_idx};

        for cong_cond_idx=1:length(congruence_conditions)

            congruence_condition=congruence_conditions{cong_cond_idx};
            condition=[congruence_condition ' - ' coherence_condition];
            % Get trials for this condition        
            cond_trials=Dremoved.indtrial(condition,'GOOD');
            
            % Only include correct trials
            if params.correct_only
                cond_trials=intersect(cond_trials, correct_trials);
            end
            
            % If this condition has any trials
            if length(cond_trials)>1                
                cond_results.rts(coherence_condition)=[cond_results.rts(coherence_condition); session_responses(cond_trials,2)];
                cond_results.rts(congruence_condition)=[cond_results.rts(congruence_condition); session_responses(cond_trials,2)];
                cond_results.rts(condition)=session_responses(cond_trials,2);
                cond_results.rts('all')=[cond_results.rts('all'); session_responses(cond_trials,2)];
                
                cond_results.pial_trials_tc(coherence_condition)=[cond_results.pial_trials_tc(coherence_condition) pial_roi_bc_foi_trials_tc(:,cond_trials)];
                cond_results.pial_trials_tc(congruence_condition)=[cond_results.pial_trials_tc(congruence_condition) pial_roi_bc_foi_trials_tc(:,cond_trials)];
                cond_results.pial_trials_tc(condition)=pial_roi_bc_foi_trials_tc(:,cond_trials);
                cond_results.pial_trials_tc('all')=[cond_results.pial_trials_tc('all') pial_roi_bc_foi_trials_tc(:,cond_trials)];               

                cond_results.wm_trials_tc(coherence_condition)=[cond_results.wm_trials_tc(coherence_condition) wm_roi_bc_foi_trials_tc(:,cond_trials)];
                cond_results.wm_trials_tc(congruence_condition)=[cond_results.wm_trials_tc(congruence_condition) wm_roi_bc_foi_trials_tc(:,cond_trials)];
                cond_results.wm_trials_tc(condition)=wm_roi_bc_foi_trials_tc(:,cond_trials);
                cond_results.wm_trials_tc('all')=[cond_results.wm_trials_tc('all') wm_roi_bc_foi_trials_tc(:,cond_trials)];
                
                cond_results.pial_trials_woi(coherence_condition)=[cond_results.pial_trials_woi(coherence_condition) pial_roi_bc_foi_trials_woi(cond_trials)];
                cond_results.pial_trials_woi(congruence_condition)=[cond_results.pial_trials_woi(congruence_condition) pial_roi_bc_foi_trials_woi(cond_trials)];
                cond_results.pial_trials_woi(condition)=pial_roi_bc_foi_trials_woi(cond_trials);
                cond_results.pial_trials_woi('all')=[cond_results.pial_trials_woi('all') pial_roi_bc_foi_trials_woi(cond_trials)];

                cond_results.wm_trials_woi(coherence_condition)=[cond_results.wm_trials_woi(coherence_condition) wm_roi_bc_foi_trials_woi(cond_trials)];
                cond_results.wm_trials_woi(congruence_condition)=[cond_results.wm_trials_woi(congruence_condition) wm_roi_bc_foi_trials_woi(cond_trials)];
                cond_results.wm_trials_woi(condition)=wm_roi_bc_foi_trials_woi(cond_trials);
                cond_results.wm_trials_woi('all')=[cond_results.wm_trials_woi('all') wm_roi_bc_foi_trials_woi(cond_trials)];
            end
        end
    end
end

x=dict();
x('all-pial')=cond_results.pial_trials_tc('all');
x('all-white')=cond_results.wm_trials_tc('all');

x_woi=dict();
x_woi('all-pial')=cond_results.pial_trials_woi('all');
x_woi('all-white')=cond_results.wm_trials_woi('all');

if params.plot
    fig=figure();
    ax=subplot(1,1,1);
    plot_power_tc(times(time_idx), cond_results.pial_trials_tc, accuracy_conditions, 'ax', ax);

    fig=figure();
    ax=subplot(1,1,1);
    plot_power_tc(times(time_idx), cond_results.wm_trials_tc, accuracy_conditions, 'ax', ax);

    fig=plot_power_woi(cond_results.pial_trials_woi, accuracy_conditions, {});

    fig=plot_power_woi(cond_results.wm_trials_woi, accuracy_conditions, {});

    fig=figure('position',[1 1 1185 950]);
    ax=subplot(2,2,1);
    plot_power_tc(times(time_idx), x, {'all-pial','all-white'}, 'ax', ax);
    ax=subplot(2,2,2);
    plot_power_tc(times(time_idx), cond_results.pial_trials_tc, coherence_conditions, 'ax', ax);
    title('pial');
    ax=subplot(2,2,3);
    plot_power_tc(times(time_idx), cond_results.pial_trials_tc, congruence_conditions,'ax', ax);
    title('pial');
    ax=subplot(2,2,4);
    plot_power_tc(times(time_idx), cond_results.pial_trials_tc, conditions, 'ax', ax);
    title('pial');

    fig=figure('position',[1 1 1185 950]);
    ax=subplot(2,2,1);
    plot_power_woi(x_woi, {'all-pial','all-white'}, {}, 'ax', ax);
    ax=subplot(2,2,2);
    plot_power_woi(cond_results.pial_trials_woi, coherence_conditions, {}, 'ax', ax);
    title('pial');
    ax=subplot(2,2,3);
    plot_power_woi(cond_results.pial_trials_woi, congruence_conditions, {}, 'ax', ax);
    title('pial');
    ax=subplot(2,2,4);
    plot_power_woi(cond_results.pial_trials_woi, conditions, {}, 'ax', ax);
    title('pial');

    fig=figure('position',[1 1 1185 950]);
    ax=subplot(2,2,1);
    plot_power_tc(times(time_idx), x, {'all-pial','all-white'}, 'ax', ax);
    ax=subplot(2,2,2);
    plot_power_tc(times(time_idx), cond_results.wm_trials_tc, coherence_conditions, 'ax', ax);
    title('white');
    ax=subplot(2,2,3);
    plot_power_tc(times(time_idx), cond_results.wm_trials_tc, congruence_conditions, 'ax', ax);
    title('white');
    ax=subplot(2,2,4);
    plot_power_tc(times(time_idx), cond_results.wm_trials_tc, conditions, 'ax', ax);
    title('white');

    fig=figure('position',[1 1 1185 950]);
    ax=subplot(2,2,1);
    plot_power_woi(x_woi, {'all-pial','all-white'}, {}, 'ax', ax);
    ax=subplot(2,2,2);
    plot_power_woi(cond_results.wm_trials_woi, coherence_conditions, {}, 'ax', ax);
    title('white');
    ax=subplot(2,2,3);
    plot_power_woi(cond_results.wm_trials_woi, congruence_conditions, {}, 'ax', ax);
    title('white');
    ax=subplot(2,2,4);
    plot_power_woi(cond_results.wm_trials_woi, conditions, {}, 'ax', ax);
    title('white');

end
cond_results.times=times(time_idx);
end
