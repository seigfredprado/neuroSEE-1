%% USER INPUT
list = 'list_m66_fam1fam2-fam2.txt';
reffile = '20181013_14_50_18';
imreg_method = 'normcorre';
mcorr_method = 'normcorre';
segment_method = 'CaImAn';
dofissa = true;
groupreg_method = 'imreg';

%% Load module folders and define data directory
[data_locn,~,err] = load_neuroSEEmodules;
if ~isempty(err)
    beep
    cprintf('Errors',err);    
    return
end

%% MouseID and experiment name
[ mouseid, expname ] = find_mouseIDexpname(list);

%% Location of processed group data for list
if dofissa, str_fissa = 'FISSA'; else, str_fissa = 'noFISSA'; end

if strcmpi(imreg_method, mcorr_method)
    grp_sdir = [data_locn 'Analysis/' mouseid '/' mouseid '_' expname '/group_proc/'...
                groupreg_method '_' imreg_method '_' segment_method '_' str_fissa '/'...
                mouseid '_' expname '_imreg_ref' reffile '/'];
else
    grp_sdir = [data_locn 'Analysis/' mouseid '/' mouseid '_' expname '/group_proc/'...
                groupreg_method '_' imreg_method '_' segment_method '_' str_fissa '/'...
                mouseid '_' expname '_imreg_ref' reffile '_' mcorr_method '/'];
end

%% Manually eliminate rois
load([grp_sdir mouseid '_' expname '_ref' reffile '_segment_output.mat'])    

roiarea_thr = 70;
masks_orig = masks; 
tsG_all = tsG; 
df_f_all = df_f; 
elim_masks_orig = elim_masks; 
clear masks tsG df_f elim_masks

% Eliminate very small rois and rois touching image border
area = zeros(size(masks_orig,3),1);
borderpix = 4;
for j = 1:size(masks_orig,3)
    mask = masks_orig(borderpix:size(masks_orig,1)-borderpix,borderpix:size(masks_orig,2)-borderpix,j);
    im = imclearborder(mask);
    c = regionprops(im,'area');
    if ~isempty(c)
        area(j) = c.Area;                    % area of each ROI
    end
end
masks = masks_orig(:,:,area>roiarea_thr);
elim_masks = masks_orig(:,:,area<roiarea_thr);
tsG = tsG_all(area>roiarea_thr,:);
df_f = df_f_all(area>roiarea_thr,:);

% ROIs overlayed on correlation image
plotopts.plot_ids = 1; % set to 1 to view the ID number of the ROIs on the plot
fig = plotContoursOnSummaryImage(corr_image, masks, plotopts);
savefig(fig, fname_fig1(1:end-4));
saveas(fig, fname_fig1(1:end-4), 'png');
close(fig);

% eliminated ROIs overlayed on correlation image
if ~isempty(elim_masks)
    plotopts.plot_ids = 1; % set to 1 to view the ID number of the ROIs on the plot
    fig = plotContoursOnSummaryImage(corr_image, elim_masks, plotopts);
end