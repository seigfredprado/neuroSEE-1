% Written by Ann Go

function frun_imreg_ROIsegment_to_PFmaps( list, reffile, slacknotify, force )

if nargin<4, force = false; end
if nargin<3, slacknotify = false; end
% if nargin<2, see line 81

tic

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% USER-DEFINED INPUT
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Basic settings
test = false;               % flag to use one of smaller files in test folder)
default = true;             % flag to use default parameters
                            % flag to force
mcorr_method = 'normcorre-nr';  % values: [normcorre, normcorre-r, normcorre-nr, fftRigid] 
                                    % CaImAn NoRMCorre method: 
                                    %   normcorre (rigid + nonrigid) 
                                    %   normcorre-r (rigid),
                                    %   normcorre-nr (nonrigid), 
                                    % fft-rigid method (Katie's)
segment_method = 'CaImAn';      % [ABLE,CaImAn]    
dofissa = true;                 % flag to implement FISSA (when false, overrides force(3) setting)
    if dofissa, str_fissa = 'FISSA'; else, str_fissa = 'noFISSA'; end
    
            % Not user-defined
            % Load module folders and define data directory
            [data_locn,comp,err] = load_neuroSEEmodules(test);
            if ~isempty(err)
                beep
                cprintf('Errors',err);    
                return
            end
            % Some security measures
            if strcmpi(comp,'hpc')
                maxNumCompThreads(32);        % max # of computational threads, must be the same as # of ncpus specified in jobscript (.pbs file)
            end

% Processing parameters (if not using default)
if ~default
    params.fr = 30.9;                         % imaging frame rate [default: 30.9]
    % ROI segmentation 
        params.ROIsegment.df_prctile = 5;     % percentile to be used for estimating baseline   [default: 5]
        params.ROIsegment.df_medfilt1 = 13;   % degree of smoothing for df_f                    [default: 23]
    % neuropil correction
    if dofissa
        params.fissa.ddf_prctile = 5;         % percentile to be used for estimating baseline   [default:5]
        params.fissa.ddf_medfilt1 = 17;       % degree of smoothing for ddf_f                   [default: 23]
    end
    % spike extraction
        params.spkExtract.bl_prctile = 85;    % percentile to be used for estimating baseline   [default:85]
        params.spkExtract.spk_SNR = 1;        % spike SNR for min spike value                   [default: 1]
        params.spkExtract.decay_time = 0.4;   % length of a typical transient in seconds        [default: 0.4]
        params.spkExtract.lam_pr = 0.99;      % false positive probability for determing lambda penalty   [default: 0.99]
    % PF mapping
        params.PFmap.Nepochs = 1;             % number of epochs for each 4 min video           [default: 1]
        params.PFmap.histsmoothFac = 7;       % Gaussian smoothing window for histogram extraction        [default: 7]
        params.PFmap.Vthr = 20;               % speed threshold (mm/s) Note: David Dupret uses 20 mm/s    [default: 20]
                                              %                              Neurotar uses 8 mm/s
        params.PFmap.prctile_thr = 95;        % percentile threshold for filtering nonPCs
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

params.methods.mcorr_method = mcorr_method;
params.methods.segment_method = segment_method;
params.methods.dofissa = dofissa;

% Default parameters
if default
    params = load_defaultparams(params);
end
if strcmpi(mcorr_method,'normcorre-nr')
    fields = {'ROIreg','fftRigid','nonrigid'};
elseif strcmpi(mcorr_method,'normcorre-r')
    fields = {'ROIreg','fftRigid','rigid'};
elseif strcmpi(mcorr_method,'normcorre')
    fields = {'ROIreg','fftRigid','rigid','nonrigid'};
end
params = rmfield(params,fields);

% Experiment name
[ mouseid, expname ] = find_mouseIDexpname(list);
listfile = [data_locn 'Digital_Logbook/lists/' list];
files = extractFilenamesFromTxtfile( listfile );
if nargin<2, reffile = files(1,:); end

% Some auto-defined parameters
if str2double(files(1,1:4)) > 2018
    params.FOV = 490;                               % FOV area = FOV x FOV, FOV in um
    params.ROIsegment.cellrad = 6;                  % expected radius of a cell (pixels)    
    params.ROIsegment.maxcells = 300;     % estimated number of cells in FOV      
else
    params.FOV = 330; 
    params.ROIsegment.cellrad = 9;            
    params.ROIsegment.maxcells = 200;       
end
release = version('-release'); % Find out what Matlab release version is running
MatlabVer = str2double(release(1:4));

% Send Ann slack message if processing has started
if slacknotify
    slacktext = [mouseid '_' expname ': starting CaImAn'];
    neuroSEE_slackNotify( slacktext );
end

%% Load image files & do ROI segmentation
sdir = [data_locn 'Analysis/' mouseid '/' mouseid '_' expname '/' mcorr_method '_' segment_method '_' str_fissa '/'...
        'collective_PFmaps_imreg_ref' reffile '/'];
if ~exist(sdir,'dir'), mkdir(sdir); end
sname = [sdir mouseid '_' expname '_ref' reffile '_masks.mat'];

if force || ~exist(sname,'file')
    for i = 1:size(files,1)
        file = files(i,:);
        if strcmpi(file,reffile)
            fname = [data_locn 'Data/' file(1:8) '/Processed/' file '/mcorr_' mcorr_method '/' file '_2P_XYT_green_mcorr.tif'];
        else
            fname = [data_locn 'Data/' file(1:8) '/Processed/' file '/mcorr_' mcorr_method '_ref' reffile '/' file '_2P_XYT_green_imreg_ref' reffile '.tif'];
        end
        fprintf('%s: reading %s\n',[mouseid '_' expname],file)
        Yii = read_file(fname);
        Y(:,:,(i-1)*size(Yii,3)+1:i*size(Yii,3)) = Yii;
    end

    % Downsample
    if size(files,1) <= 7
        k = 5;
    elseif size(files,1) <= 10
        k = 7;
    elseif size(files,1) <= 13
        k = 9;
    else
        k = round( size(files,1)*7420/11000 );
    end
    imG = Y(:,:,1:k:end);
    clear Y

    %% ROI segmentation
    if str2double(file(1:4)) > 2018
            cellrad = 6;                    % expnameected radius of a cell (pixels)    
            maxcells = 300;                 % estimated number of cells in FOV      
        else
            cellrad = 9;            
            maxcells = 200;         
    end

    if strcmpi(segment_method,'CaImAn')
        [~, masks, corr_image] = CaImAn( imG, file, maxcells, cellrad );
        clear imG 
    end

    % Output
    % ROIs overlayed on correlation image
    plotopts.plot_ids = 1; % set to 1 to view the ID number of the ROIs on the plot
    fig = plotContoursOnSummaryImage(corr_image, masks, plotopts);

    % save masks.mat
    for i = 1:size(files,1)
        file = files(i,:);
        if strcmpi(file,reffile)
            sdir = [data_locn 'Data/' file(1:8) '/Processed/' file '/mcorr_' mcorr_method '/' segment_method '_' mouseid '_' expname '/'];
            if ~exist(sdir,'dir'), mkdir(sdir); end
            sname = [sdir mouseid '_' expname '_ref' reffile '_masks.mat'];
        else
            sdir = [data_locn 'Data/' file(1:8) '/Processed/' file '/mcorr_' mcorr_method '_ref' reffile '/' segment_method '_' mouseid '_' expname '/'];
            if ~exist(sdir,'dir'), mkdir(sdir); end
            sname = [sdir mouseid '_' expname '_ref' reffile '_masks.mat'];
        end
        save(sname,'masks','corr_image');
        savefig(fig,[sdir mouseid '_' expname '_ref' reffile '_ROIs']);
        saveas(fig,[sdir mouseid '_' expname '_ref' reffile '_ROIs'],'png');
    end
    save(sname,'masks','corr_image');
    savefig(fig,[sdir mouseid '_' expname '_ref' reffile '_ROIs']);
    saveas(fig,[sdir mouseid '_' expname '_ref' reffile '_ROIs'],'png');
    close(fig);
else
    fprintf('%s: Found ROI segmentation results. Proceeding to FISSA correction\n',[mouseid '_' expname])
    masks = load(sname,'masks');
    masks = masks.masks;
end

%% FISSA, spike extraction, tracking data loading, PF mapping
sname = [sdir mouseid '_' expname '_ref' reffile '_fissa_spike_track_data.mat'];

if force || ~exist(sname,'file')
    % initialise matrices
    SdtsG = []; Sddf_f = []; Sspikes = [];
    SdownData.phi = [];
    SdownData.x = [];
    SdownData.y = [];
    SdownData.speed = [];
    SdownData.r = [];
    SdownData.time = [];

    for id = 1:size(files,1)
        file = files(id,:);
        if strcmpi(file,reffile)
            tiffile = [data_locn 'Data/' file(1:8) '/Processed/' file '/mcorr_' mcorr_method '/' file '_2P_XYT_green_mcorr.tif'];
            fissadir = [data_locn 'Data/' file(1:8) '/Processed/' file '/mcorr_' mcorr_method '/' segment_method '_' mouseid '_' expname '/FISSA/'];
        else
            tiffile = [data_locn 'Data/' file(1:8) '/Processed/' file '/mcorr_' mcorr_method '_ref' reffile '/' file '_2P_XYT_green_imreg_ref' reffile '.tif'];
            fissadir = [data_locn 'Data/' file(1:8) '/Processed/' file '/mcorr_' mcorr_method '_ref' reffile '/' segment_method '_' mouseid '_' expname '/FISSA/'];
        end
        if ~exist( fissadir, 'dir' ), mkdir( fissadir ); end

        %% FISSA
        if force || ~exist([fissadir file '_' mouseid '_' expname '_ref' reffile '_fissa_output.mat'],'file')
            fprintf('%s: doing fissa\n',[mouseid '_' expname '_' file]);
            fname_mat_temp = [fissadir 'FISSAout/matlab.mat'];
            if force || and(~exist([fissadir file '_' mouseid '_' expname '_ref' reffile '_fissa_output.mat'],'file'), ~exist(fname_mat_temp,'file'))
                runFISSA( masks, tiffile, fissadir );
            end

            result = load(fname_mat_temp,'result');

            % Convert decontaminated timeseries cell array structure to a matrix
            dtsG = zeros(size(masks,3),size(result.result.cell0.trial0,2));
            for k = 1:numel(fieldnames(result.result))
                dtsG(k,:) = result.result.(['cell' num2str(k-1)]).trial0(1,:);
            end

            % Calculate df_f
            ddf_f = zeros(size(dtsG));
            xddf_prctile = params.fissa.ddf_prctile;
            for k = 1:size(dtsG,1)
                x = lowpass( medfilt1(dtsG(k,:),params.fissa.ddf_medfilt1), 1, params.fr );
                fo = ones(size(x)) * prctile(x,xddf_prctile);
                while fo == 0
                    fo = ones(size(x)) * prctile(x,xddf_prctile+5);
                    xddf_prctile = xddf_prctile+5;
                end
                ddf_f(k,:) = (x - fo) ./ fo;
            end

            fname_fig = [fissadir file '_' mouseid '_' expname '_ref' reffile];
            plotfissa(dtsG, ddf_f, fname_fig);
            save([fissadir file '_' mouseid '_' expname '_ref' reffile '_fissa_output.mat'],'dtsG','ddf_f');
        else
            fprintf('%s: loading fissa output\n',[mouseid '_' expname '_' file]);
            M = load([fissadir file '_' mouseid '_' expname '_ref' reffile '_fissa_output.mat']);
            dtsG = M.dtsG;
            ddf_f = M.ddf_f;
            if ~exist([fissadir file '_' mouseid '_' expname '_ref' reffile '_fissa_result.fig'],'file')
                fname_fig = [fissadir file '_' mouseid '_' expname '_ref' reffile];
                plotfissa(dtsG, ddf_f, fname_fig);
            end
        end

        %% Spike extraction
        if force || ~exist([fissadir file '_' mouseid '_' expname '_ref' reffile '_spikes.mat'],'file')
            fprintf('%s: extracting spikes\n', [mouseid '_' expname '_' file]);
            C = ddf_f;
            N = size(C,1); T = size(C,2);

            for k = 1:N
                fo = ones(1,T) * prctile(C(k,:),params.spkExtract.bl_prctile);
                C(k,:) = (C(k,:) - fo); % ./ fo;
            end
            spikes = zeros(N,T);
            for k = 1:N
                spkmin = params.spkExtract.spk_SNR*GetSn(C(k,:));
                lam = choose_lambda(exp(-1/(params.fr*params.spkExtract.decay_time)),GetSn(C(k,:)),params.spkExtract.lam_pr);

                [~,spk,~] = deconvolveCa(C(k,:),'ar2','method','thresholded','optimize_pars',true,'maxIter',20,...
                                        'window',150,'lambda',lam,'smin',spkmin);
                spikes(k,:) = spk(:);
            end

            fname_fig = [fissadir file '_' mouseid '_' expname '_ref' reffile];
            plotspikes(spikes, fname_fig);
            save([fissadir file '_' mouseid '_' expname '_ref' reffile '_spikes.mat'],'spikes');
        else
            fprintf('%s: loading spike data\n', [mouseid '_' expname '_' file]);
            M = load([fissadir file '_' mouseid '_' expname '_ref' reffile '_spikes.mat']);
            spikes = M.spikes;
            if ~exist([fissadir file '_' mouseid '_' expname '_ref' reffile '_spikes.fig'],'file')
                plotspikes(spikes, [fissadir file '_' mouseid '_' expname '_ref' reffile]);
            end
        end

        %% Tracking data
        fprintf('%s: loading tracking data\n', [mouseid '_' expname '_' file]);
        if force || ~exist([fissadir file '_' mouseid '_' expname '_ref' reffile '_downData.mat'],'file')
            trackfile = findMatchingTrackingFile(data_locn, file, 0);
            c = load_trackfile(data_locn, files(id,:), trackfile, 0);
            downData = downsample_trackData( c, spikes, params.fr );

            save([fissadir file '_' mouseid '_' expname '_ref' reffile '_downData.mat'],'downData');
        else
            M = load([fissadir file '_' mouseid '_' expname '_ref' reffile '_downData.mat']);
            downData = M.downData;
        end

        % Superset arrays
        SdtsG = [SdtsG dtsG];
        Sddf_f = [Sddf_f ddf_f];
        Sspikes = [Sspikes spikes];

        SdownData.phi = [SdownData.phi; downData.phi];
        SdownData.x = [SdownData.x; downData.x];
        SdownData.y = [SdownData.y; downData.y];
        SdownData.speed = [SdownData.speed; downData.speed];
        SdownData.r = [SdownData.r; downData.r];
        SdownData.time = [SdownData.time; downData.time];
    end


    %% Plot and save superset arrays
    % raw timeseries & dF/F
    if ~exist([sdir mouseid '_' expname '_ref' reffile '_fissa_result.fig'],'file') ||...
       ~exist([sdir mouseid '_' expname '_ref' reffile '_fissa_df_f.fig'],'file') 
        fname_fig = [sdir mouseid '_' expname '_ref' reffile];
        plotfissa(SdtsG, Sddf_f, fname_fig);
    end
    clear dtsG ddf_f

    % spikes
    % NOTE: plotting spikes results in fatal segmentation fault (core dumped)
    % if ~exist([sdir expname str_env '_ref' reffile '_spikes.fig'],'file')
    %     fig = figure;
    %     iosr.figures.multiwaveplot(1:size(Sspikes,2),1:size(Sspikes,1),Sspikes,'gain',5); yticks([]); xticks([]);
    %     title('Spikes','Fontweight','normal','Fontsize',12);
    %     savefig(fig,[sdir expname str_env '_ref' reffile '_spikes']);
    %     saveas(fig,[sdir expname str_env '_ref' reffile '_spikes'],'png');
    %     close(fig);
    % end
    clear spikes

    % Concatenated data
    dtsG = SdtsG;
    ddf_f = Sddf_f;
    spikes = Sspikes;
    trackData = SdownData;

    fprintf('%s: saving fissa, spike, track data', [mouseid '_' expname]);
    save(sname,'dtsG','ddf_f','spikes','trackData');

else
    c = load(sname);
    dtsG = c.dtsG;
    ddf_f = c.ddf_f;
    spikes = c.spikes;
    trackData = c.trackData;
end

%% PFmapping
if any(trackData.r < 100)
    params.mode_dim = '2D';         % open field
    params.PFmap.Nbins = [16, 16];  % number of location bins in [x y]               
else 
    params.mode_dim = '1D';         % circular linear track
    params.PFmap.Nbins = 30;        % number of location bins               
end

Nepochs = params.PFmap.Nepochs;
if force || ~exist([sdir mouseid '_' expname '_ref' reffile '_PFmap_output.mat'],'file')
    fprintf('%s: generating PFmaps\n', [mouseid '_' expname]);
    if strcmpi(params.mode_dim,'1D')
        % Generate place field maps
        [ occMap, hist, asd, ~, activeData ] = generatePFmap_1d( spikes, trackData, params, true );
        
        % If 1D, sort place field maps 
        [ hist.sort_pfMap, hist.sortIdx ] = sortPFmap_1d( hist.pfMap, hist.infoMap, Nepochs );
        [ asd.sort_pfMap, asd.sortIdx ] = sortPFmap_1d( asd.pfMap, asd.infoMap, Nepochs );
        for en = 1:Nepochs
            hist.sort_pfMap_sm(:,:,en) = hist.pfMap_sm(hist.sortIdx(:,en),:,en);
            hist.sort_normpfMap(:,:,en) = hist.normpfMap(hist.sortIdx(:,en),:,en);
            hist.sort_normpfMap_sm(:,:,en) = hist.normpfMap_sm(hist.sortIdx(:,en),:,en);

            asd.sort_pfMap(:,:,en) = asd.pfMap(asd.sortIdx(:,en),:,en);
            asd.sort_normpfMap(:,:,en) = asd.normpfMap(asd.sortIdx(:,en),:,en);
        end

        % Make plots
        plotPF_1d(occMap, hist, asd, normspkMap_pertrial, ytick_files, true, [sdir 'PFmaps/'], ...
                  [mouseid '_' expname '_ref' reffile], true)
        
        % Save output
        output.occMap = occMap;
        output.hist = hist;
        output.asd = asd;
        output.activeData = activeData;
        output.params = params.PFmap;
        save([sdir mouseid '_' expname '_ref' reffile '_PFmap_output.mat'],'-struct','output');
    
    else % '2D'
        [occMap, spkMap, spkIdx, hist, asd, ~, activeData] = generatePFmap_2d(spikes, [], trackData, params, false);

         % Make plots
        plotPF_2d(spkMap, activeData, hist, asd);

        % Save output
        output.occMap = occMap;
        output.spkMap = spkMap;
        output.spkIdx = spkIdx;
        output.hist = hist;
        output.asd = asd;
        output.activeData = activeData;
        output.params = params.PFmap;
        save([sdir mouseid '_' expname '_ref' reffile '_PFmap_output.mat'],'-struct','output');
    end
end

% Send Ann slack message if processing has finished
if slacknotify
    slacktext = [expname ': CaImAn FINISHED. No errors!'];
    neuroSEE_slackNotify( slacktext );
end

t = toc;
str = sprintf('%s: Processing done in %g hrs\n', [mouseid '_' expname], round(t/3600,2));
cprintf(str)

end