% Written by Ann Go
% 
% This script runs the complete data processing pipeline for a single
% file. Processing steps include:
% (1) motion correction (and dezippering)
% (2) roi segmentation 
% (3) neuropil decontamination and timeseries extraction
% (4) spike extraction
% (5) tracking data extraction
% (6) place field mapping
%
% The sections labeled "USER:..." require user input

clear; close all;
tic

%% USER: Set basic settings
                            % Set to
test = 1;                   % [0,1] 1: debug mode (this will use one of smaller files in test folder)
default = 1;                % [0,1] 1: default parameters
                            % 
force = [0;...              % [0,1] 1: force raw to tif conversion of images
         0;...              % [0,1] 1: force motion correction even if motion corrected images exist
         0];                % [0,1] 1: force pipeline to redo all steps after motion correction
                            %       0, processing step is skipped if output of said
                            %          step already exists in individual file directory.
mcorr_method = 'normcorre'; % [normcorre,fftRigid] CaImAn NoRMCorre method, fft-rigid method (Katie's)
segment_method = 'CaImAn';  % [ABLE,CaImAn] 
fissa_yn = true;            % [true,false] implement FISSA?


%% Load module folders and define data directory

[data_locn,err] = load_neuroSEEmodules(test);
if ~isempty(err)
    beep
    cprintf('Errors',err);    
    return
end


%% USER: Specify file

file = '20190406_20_38_41'; 


%% USER: Set parameters (if not using default)

if ~default
    % motion correction
        % neurosee method
        if strcmpi(mcorr_method,'fftRigid')
            params.imscale = 1;             % image downsampling factor                                             [default: 1]
            params.Nimg_ave = 10;           % no. of images to be averaged for calculating pixel shift (zippering)  [default: 10]
            params.refChannel = 'green';    % channel to be used for calculating image shift (green,red)            [default: 'green']
            params.redoT = 300;             % no. of frames at start of file to redo motion correction for after 1st iteration [default: 300]
        end
        % NoRMCorre
        if strcmpi(mcorr_method,'normcorre')
            params.nonrigid = NoRMCorreSetParms(...
                        'd1',512,...        % width of image [default: 512]  *Regardless of user-inputted value, neuroSEE_motioncorrect reads this 
                        'd2',512,...        % length of image [default: 512] *value from actual image    
                        'grid_size',[32,32],...     % default: [32,32]
                        'overlap_pre',[32,32],...   % default: [32,32]
                        'overlap_post',[32,32],...  % default: [32,32]
                        'iter',1,...                % default: 1
                        'use_parallel',false,...    % default: false
                        'max_shift',50,...          % default: 50
                        'mot_uf',4,...              % default: 4
                        'bin_width',200,...         % default: 200
                        'max_dev',3,...             % default: 3
                        'us_fac',50,...             % default: 50
                        'init_batch',200);          % default: 200
        end
    % ROI segmentation 
        params.cellrad = 10;        % expected radius of a cell (pixels)    [default: 10]
        params.maxcells = 200;      % estimated number of cells in FOV      [default: 200]
    % spike extraction
        params.g = 0.997;               % fluorescence impulse factor (OASIS)   [default: 0.997]
        params.lambda = 120;            % sparsity penalty (OASIS)              [default: 120]
    % PF mapping
        params.mode_dim = '1D';         % [1D,2D]                               [default: 1D]
        params.FOV = 330;               % FOV area = FOV x FOV, FOV in um       [default: 330]
        params.mode_method = 'hist';    % [ASD,hist]                            [default: hist]
        params.imrate = 30.9;           % image scanning frame rate             [default: 30.9]
        params.Nbins = 30;              % number of location bins               [default: 30]
        params.Nepochs = 1;             % number of epochs for each 4 min video [default: 1]
        params.smoothFac = 10;          % Gaussian smoothing window for histogram estimation        [default: 10]
        params.Vthr = 20;               % speed threshold (mm/s) Note: David Dupret uses 20 mm/s    [default: 20]
                                        %                              Neurotar uses 8 mm/s
end

if test
    params.maxcells = 60;  
end


%% Default parameters

if default
    params = load( 'default_params.mat' );
    
    % Remove irrelevant parameters (i.e. those for the unchosen motion correction method)
    if strcmpi(mcorr_method,'normcorre')
        fields = {'imscale','Nimg_ave','refChannel','redoT'};
        params = rmfield(params,fields);
    else
        params = rmfield(params,'nonrigid');
    end
end

params.mcorr_method = mcorr_method;
params.segment_method = segment_method;
params.fissa_yn = fissa_yn;


%% Check if file has been processed. If not, continue processing unless forced to overwrite 
% existing processed data

if checkforExistingProcData(data_locn, file, mcorr_method, segment_method, fissa_yn)
    if ~any(force)
        beep
        str = sprintf( '%s: File has been processed with specified options. Skipping processing.\n', file );
        cprintf(str)
        return
    else
        if force(1)>0
            force(2) = 1; force(3) = 1; % because redoing raw to tif conversion step affects all succeeding steps
        else
            if force(2)>0
                force(3) = 1; % because redoing motion correction step affects all succeeding steps
            end
        end
    end
end


%% Image files
% force(1) = 1 forces raw images to be loaded
% force(1) = 0 loads tif files if they exist, but reverts to raw images if tif
%           files don't exist
% force(2) = 1 forces motion correction to be done
% If not forced to overwrite motion corrected files, find out if they
% exist. Only load non-motion corrected files if they don't

mcorrIm_yn = checkfor_mcorrIm( data_locn, file, mcorr_method );

if ~all( [~force(2), mcorrIm_yn])
    [imG,imR] = load_imagefile( data_locn, file, force(1) );
else
    imG = []; imR = [];
end

            
%% Motion correction
% Saved in file folder: 
% (1) motion corrected tif files 
% (2) summary fig & pdf, 
% (3) mat with fields 
%       green.[ meanframe, meanregframe ]
%       red.[ meanframe, meanregframe ]
%       template
%       shifts
%       params

[imG, imR, ~, params] = neuroSEE_motionCorrect( imG, imR, data_locn, file, mcorr_method, params, force(2) );


%% ROI segmentation
% Saved in file folder: 
% (1) correlation image with ROIs (fig, pdf)
% (2) mat with fields {tsG, df_f, masks, corr_image, params}

[tsG, df_f, masks, corr_image, params] = neuroSEE_segment( imG, mean(imR,3), data_locn, file, mcorr_method, segment_method, params, force(3) );


%% Run FISSA to extract neuropil-corrected time-series
% Saved in file folder: mat file with fields {tsG, df_f, masks}

% if fissa_yn
%     [rtsG, rdf_f] = neuroSEE_neuropilDecon( masks, data_locn, file, mcorr_method, segment_method, force(3) );
% end


%% Calculate ratiometric Ca time series (R) and extract spikes
% Saved: mat with fields {R, spikes, params}

% % [R, spikes, params] = neuroSEE_extractSpikes( tsG, tsR, data_locn, file, params, force );

%% Find tracking file then load it
% Saved: fig & pdf of trajectory
%        mat with fields {time, r, phi, x, y , speed, w, alpha, TTLout, filename}

% % fname_track = findMatchingTrackingFile(data_locn, file, force);
% % trackdata = load_trackfile(data_locn,file, fname_track, force);

% Generate place field maps
% Saved: fig & pdf of summary consisting of occMap, infoMap, spikeMap and placeMap
%        mat file with fields {occMap, spikeMap, infoMap, placeMap, downData, activeData,...
%                               placeMap_smooth, sorted_placeMap, sortIdx, params}

% % [occMap, spikeMap, infoMap, placeMap, downData, activeData, placeMap_smooth, sorted_placeMap, normsorted_placeMap, sortIdx,...
% %     params] = neuroSEE_mapPF( spikes, trackdata, data_locn, file, params, force);
% 
% %% Save output. These are all the variables needed for viewing data with GUI
% 
% % save(fname_allData,'file','mcorr_output','tsG','tsR','masks','mean_imratio','R','spikes',...
% %                     'fname_track','occMap','spikeMap','infoMap','placeMap','downData','activeData',...
% %                     'placeMap_smooth','sorted_placeMap','sortIdx','params');

t = toc;
str = sprintf('%s: Processing done in %g hrs', file, round(t/3600,2));
cprintf(str)