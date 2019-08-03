% Written by Ann Go

function frun_fissa2maps_expbatch( expname, expsubname, list, reffile )

tic 

%% Load module folders and define data directory

test = false;                   % flag to use one of smaller files in test folder)
[data_locn,comp,err] = load_neuroSEEmodules(test);
if ~isempty(err)
    beep
    cprintf('Errors',err);    
    return
end
if strcmpi(comp,'hpc')
    maxNumCompThreads(8);      % max # of computational threads, must be the same as # of ncpus specified in jobscript (.pbs file)
end

%% Parameters
params = load( 'default_params.mat' );

% Remove irrelevant parameters 
params = rmfield(params,'fftRigid');
fields = {'df_prctile','df_medfilt1'};
params.ROIsegment = rmfield(params.ROIsegment,fields);
params = rmfield(params,'nonrigid');

mouseid = expname(1:3);
if isempty(expsubname)
    sdir = [data_locn 'Analysis/' mouseid '/' expname '/'];
    expsubname = expname;
else
    sdir = [data_locn 'Analysis/' mouseid '/' expname '/' expsubname '/'];
end
if ~exist(sdir,'dir'), mkdir(sdir); end

% files
files = extractFilenamesFromTxtfile( list );

% masks
file = files(1,:);
if strcmpi(file,reffile)
    matfile = [data_locn 'Data/' file(1:8) '/Processed/' file '/mcorr_normcorre/CaImAn_' expname '/' expname '_masks.mat'];
else
    matfile = [data_locn 'Data/' file(1:8) '/Processed/' file '/mcorr_normcorre_ref' reffile '/CaImAn_' expname '/' expname '_masks.mat'];
end
masks = load(matfile,'masks');
masks = masks.masks;

% initialise matrices
SdtsG = []; Sddf_f = []; Sspikes = [];
SdownData.phi = [];
SdownData.x = [];
SdownData.y = [];
SdownData.speed = [];
SdownData.r = [];

for i = 1:size(files,1)
    file = files(i,:);
    if strcmpi(file,reffile)
        tiffile = [data_locn 'Data/' file(1:8) '/Processed/' file '/mcorr_normcorre/' file '_2P_XYT_green_mcorr.tif'];
        fissadir = [data_locn 'Data/' file(1:8) '/Processed/' file '/mcorr_normcorre/CaImAn_' expname '/FISSA/'];
    else
        tiffile = [data_locn 'Data/' file(1:8) '/Processed/' file '/mcorr_normcorre_ref' reffile '/' file '_2P_XYT_green_imreg_ref' reffile '.tif'];
        fissadir = [data_locn 'Data/' file(1:8) '/Processed/' file '/mcorr_normcorre_ref' reffile '/CaImAn_' expname '/FISSA/'];
    end
    if ~exist( fissadir, 'dir' ), mkdir( fissadir ); end
    
    % FISSA
    if ~exist([fissadir expsubname '_fissa_output.mat'],'file')
        fprintf('%s: doing fissa\n',[expsubname '_' file]);
        fname_mat_temp = [fissadir 'FISSAout/matlab.mat'];
        if ~exist(fname_mat_temp,'file')
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
        for m = 1:size(dtsG,1)
            x = lowpass( medfilt1(dtsG(i,:),params.fissa.ddf_medfilt1), 1, params.fr );
            fo = ones(size(x)) * prctile(x,xddf_prctile);
            while fo == 0
                fo = ones(size(x)) * prctile(x,xddf_prctile+5);
                xddf_prctile = xddf_prctile+5;
            end
            ddf_f(m,:) = (x - fo) ./ fo;
        end
        
        save([fissadir expsubname '_fissa_output.mat'],'dtsG','ddf_f');
    else
        fprintf('%s: loading fissa output\n',[expsubname '_' file]);
        M = load([fissadir expsubname '_fissa_output.mat']);
        dtsG = M.dtsG;
        ddf_f = M.ddf_f;
    end

    % tracking data
    fprintf('%s: loading tracking data\n', [expsubname '_' file]);
    if ~exist([fissadir expsubname '_downData.mat'],'file')
        trackfile = findMatchingTrackingFile(data_locn, file, 0);
        c = load_trackfile(data_locn, files(i,:), trackfile, 0);
        x = c.x;
        y = c.y;
        r = c.r;
        phi = c.phi;
        speed = c.speed;
        tracktime = c.time;

        % Pre-process tracking data
        t0 = tracktime(1);                  % initial time in tracking data
        Nt = size(dtsG,2);                % number of timestamps for spikes

        % Convert -180:180 to 0:360
        if min(phi)<0
           phi(phi<0) = phi(phi<0)+360;
        end

        % generate imaging timestamps using known image frame rate
        dt = 1/params.fr;
        t = (t0:dt:Nt*dt)';

        % Downsample tracking to Ca trace
        downData.phi = interp1(tracktime,phi,t,'linear');
        downData.x = interp1(tracktime,x,t,'linear');
        downData.y = interp1(tracktime,y,t,'linear');
        downData.speed = interp1(tracktime,speed,t,'linear'); % mm/s
        downData.r = interp1(tracktime,r,t,'linear'); % mm/s
        downData.time = t;

        save([fissadir expsubname '_downData.mat'],'downData');
    else
        M = load([fissadir expsubname '_downData.mat']);
        downData = M.downData;
    end

    % Spike extraction
    if ~exist([fissadir expsubname '_spikes.mat'],'file')
        fprintf('%s: extracting spikes\n', [expsubname '_' file]);
        C = ddf_f;
        N = size(C,1); T = size(C,2);

        for n = 1:N
            fo = ones(1,T) * prctile(C(n,:),params.spkExtract.bl_prctile);
            C(n,:) = (C(n,:) - fo); % ./ fo;
        end
        spikes = zeros(N,T);
        for n = 1:N
            spkmin = params.spkExtract.spk_SNR*GetSn(C(n,:));
            lam = choose_lambda(exp(-1/(params.fr*params.spkExtract.decay_time)),GetSn(C(n,:)),params.spkExtract.lam_pr);

            [~,spk,~] = deconvolveCa(C(n,:),'ar2','method','thresholded','optimize_pars',true,'maxIter',20,...
                                    'window',150,'lambda',lam,'smin',spkmin);
            spikes(n,:) = spk(:);
        end
        save([fissadir expsubname '_spikes.mat'],'spikes');
    else
        fprintf('%s: loading spike data\n', [expsubname '_' file]);
        M = load([fissadir expsubname '_spikes.mat']);
        spikes = M.spikes;
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
    SdownData.time = downData.time;
end


%% Plot and save superset arrays
% raw timeseries
if ~exist([sdir expsubname '_fissa_result.fig'],'file')
    fig = figure;
    iosr.figures.multiwaveplot(1:size(SdtsG,2),1:size(SdtsG,1),SdtsG,'gain',5); yticks([]); xticks([]); 
    title('Fissa-corrected raw timeseries','Fontweight','normal','Fontsize',12); 
    savefig(fig,[sdir expsubname '_fissa_result']);
    saveas(fig,[sdir expsubname '_fissa_result'],'png');
    close(fig); 
end
clear dtsG
dtsG = SdtsG;

% dF/F
if ~exist([sdir expsubname '_fissa_df_f.fig'],'file')
    fig = figure;
    iosr.figures.multiwaveplot(1:size(Sddf_f,2),1:size(Sddf_f,1),Sddf_f,'gain',5); yticks([]); xticks([]); 
    title('Fissa-corrected dF/F','Fontweight','normal','Fontsize',12); 
    savefig(fig,[sdir expsubname '_fissa_df_f']);
    saveas(fig,[sdir expsubname '_fissa_df_f'],'png');
    close(fig); 
end
clear ddf_f
ddf_f = Sddf_f;

% spikes
% NOTE: plotting spikes results in fatal segmentation fault (core dumped)
% if ~exist([sdir expsubname '_spikes.fig'],'file')
%     fig = figure;
%     iosr.figures.multiwaveplot(1:size(Sspikes,2),1:size(Sspikes,1),Sspikes,'gain',5); yticks([]); xticks([]);
%     title('Spikes','Fontweight','normal','Fontsize',12);
%     savefig(fig,[sdir expsubname '_spikes']);
%     saveas(fig,[sdir expsubname '_spikes'],'png');
%     close(fig);
% end
clear spikes
spikes = Sspikes;

% tracking data
t0 = SdownData.time(1);
Nt = size(dtsG,2);                % number of timestamps for spikes
dt = 1/params.fr;
t = (t0:dt:Nt*dt)';
SdownData.time = t;
trackData = SdownData;

fprintf('%s: saving fissa, spike, track data',expsubname);
save([sdir expsubname '_fissa_spike_track_data.mat'],'dtsG','ddf_f','spikes','trackData');


%% PFmapping
if any(trackData.r < 100)
    params.mode_dim = '2D'; % open field
    params.PFmap.Nbins = [16, 16]; % number of location bins in [x y]               
else 
    params.mode_dim = '1D'; % circular linear track
    params.PFmap.Nbins = 150;      % number of location bins               
end

Nepochs = params.PFmap.Nepochs;
if ~exist([sdir expsubname '_PFmap_output.mat'],'file')
    fprintf('%s: generating PFmaps\n', expsubname);
    if strcmpi(params.mode_dim,'1D')
        % Generate place field maps
        [occMap, hist, asd, ~, activeData] = generatePFmap_1d(spikes, [], trackData, params, false);

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
        makeplot_1d(occMap, hist, asd);

        % Save output
        output.occMap = occMap;
        output.hist = hist;
        output.asd = asd;
        output.activeData = activeData;
        output.params = params.PFmap;
        save([sdir expsubname '_PFmap_output.mat'],'-struct','output');
    else % '2D'
        [occMap, spkMap, spkIdx, hist, asd, ~, activeData] = generatePFmap_2d(spikes, imtime, trackData, params, false);

         % Make plots
        makeplot_2d(spkMap, activeData, hist, asd);

        % Save output
        output.occMap = occMap;
        output.spkMap = spkMap;
        output.spkIdx = spkIdx;
        output.hist = hist;
        output.asd = asd;
        output.activeData = activeData;
        output.params = params.PFmap;
        save([sdir expsubname '_PFmap_output.mat'],'-struct','output');
    end
end


t = toc;
str = sprintf('%s: Processing done in %g hrs\n', expsubname, round(t/3600,2));
cprintf(str)

function makeplot_1d(occMap, hist, asd)
    Npcs = length(hist.pcIdx);
    Npcs_asd = length(asd.pcIdx);

    % summary of occMap, spkMaps, pfMaps
    for e = 1:Nepochs
        fh = figure('Position',[1087 648 800 800]);
        subplot(10,8,2:4); imagesc(occMap(e,:));
            xticks([]); yticks([]); ylabel('Occ');
            title('Histogram estimation'); colorbar;
        subplot(10,8,6:8); imagesc(occMap(e,:));
            xticks([]); yticks([]); ylabel('Occ');
            title('ASD'); colorbar;

        subplot(10,8,[10:12,18:20,26:28]);
            imagesc(hist.spkMap(hist.sortIdx(:,e),:,e));
            xticks([]);
            yticks([1 Npcs]); ylabel('Cell #'); 
            title('Spike map'); colorbar;
        subplot(10,8,[14:16,22:24,30:32]);
            imagesc(asd.spkMap(asd.sortIdx(:,e),:,e));
            xticks([]);
            yticks([1 Npcs_asd]);  ylabel('Cell #'); 
            title('Spike map'); colorbar;

        subplot(10,8,[33,41,49]); imagesc(hist.infoMap(hist.sortIdx,1,e));
            xticks([]);
            yticks([1 Npcs]); ylabel('Cell #'); 
            title('Max MI'); colorbar;
        subplot(10,8,[34:36,42:44,50:52]);    
            imagesc(hist.sort_pfMap(:,:,e)); 
            xticks([]); yticks([1 Npcs]);
            title('Place field map'); colorbar;
        subplot(10,8,[37,45,53]); imagesc(asd.infoMap(asd.sortIdx,1,e));
            xticks([]);
            yticks([1 Npcs_asd]); 
            title('Max MI'); colorbar;
        subplot(10,8,[38:40,46:48,54:56]);    
            imagesc(asd.sort_pfMap(:,:,e)); 
            yticks([1 Npcs_asd]);
            xticks([1 15 30]); xticklabels([1 50 100]);
            xlabel('Position (cm)');
            title('Place field map'); colorbar;

        subplot(10,8,[58:60,66:68,74:76]);    
            imagesc(hist.sort_pfMap_sm(:,:,e)); 
            yticks([1 Npcs]); ylabel('Cell #');
            xticks([1 15 30]); xticklabels([1 50 100]);
            xlabel('Position (cm)');
            title('Smoothened pf map'); colorbar; 

        if Nepochs == 1
            fname_fig = [sdir '/PFmaps/' expsubname '_PFmaps'];
        else
            fname_fig = [sdir '/PFmaps/' expsubname '_PFmaps_' num2str(e) 'of' num2str(Nepochs) 'ep'];
        end
        if ~exist([sdir '/PFmaps/']), mkdir([sdir '/PFmaps/']); end
        savefig( fh, fname_fig );
        saveas( fh, fname_fig, 'png' );
        close( fh );
    end

    % summary of occMap, spkMaps, normpfMaps
    for e = 1:Nepochs
        fh = figure('Position',[1087 648 800 800]);
        subplot(10,8,2:4); imagesc(occMap(e,:));
            xticks([]); yticks([]); ylabel('Occ');
            title('Histogram estimation'); colorbar;
        subplot(10,8,6:8); imagesc(occMap(e,:));
            xticks([]); yticks([]); ylabel('Occ');
            title('ASD'); colorbar;

        subplot(10,8,[10:12,18:20,26:28]);
            imagesc(hist.normspkMap(hist.sortIdx(:,e),:,e));
            xticks([]);
            yticks([1 Npcs]); ylabel('Cell #'); 
            title('Normalised spk map'); colorbar;
        subplot(10,8,[14:16,22:24,30:32]);
            imagesc(asd.normspkMap(asd.sortIdx(:,e),:,e));
            xticks([]);
            yticks([1 Npcs_asd]);  ylabel('Cell #'); 
            title('Normalised spk map'); colorbar;

        subplot(10,8,[33,41,49]); imagesc(hist.infoMap(hist.sortIdx,1,e));
            xticks([]);
            yticks([1 Npcs]); ylabel('Cell #'); 
            title('Max MI'); colorbar;
        subplot(10,8,[34:36,42:44,50:52]);    
            imagesc(hist.sort_normpfMap(:,:,e)); 
            xticks([]); yticks([1 Npcs]);
            title('Normalised pf map'); colorbar;
        subplot(10,8,[37,45,53]); imagesc(asd.infoMap(asd.sortIdx,1,e));
            xticks([]);
            yticks([1 Npcs_asd]); 
            title('Max MI'); colorbar;
        subplot(10,8,[38:40,46:48,54:56]);    
            imagesc(asd.sort_normpfMap(:,:,e)); 
            yticks([1 Npcs_asd]);
            xticks([1 15 30]); xticklabels([1 50 100]);
            xlabel('Position (cm)');
            title('Normalised pf map'); colorbar;

        subplot(10,8,[58:60,66:68,74:76]);    
            imagesc(hist.sort_normpfMap_sm(:,:,e)); 
            yticks([1 Npcs]); ylabel('Cell #');
            xticks([1 15 30]); xticklabels([1 50 100]);
            xlabel('Position (cm)');
            title('Norm smooth pf map'); colorbar; 

        if Nepochs == 1
            fname_fig = [sdir '/PFmaps/' expsubname '_normPFmaps'];
        else
            fname_fig = [sdir '/PFmaps/' expsubname '_normPFmaps_' num2str(e) 'of' num2str(Nepochs) 'ep'];
        end
        savefig( fh, fname_fig );
        saveas( fh, fname_fig, 'png' );
        close( fh );
    end

    % per trial spike maps
    [nRow, nCol] = getnRownCol(Npcs);
    nPlot = nRow*nCol;

    % histogram
    Ntrials = size(hist.spkMap_pertrial,1);
    for ii=0:Npcs/nPlot
        fh = figure;
        ha = tight_subplot(nRow,nCol,[.01 .01],[.01 .05],[.01 .01]);
        for jj=0:nPlot-1
            if (ii*nPlot+jj+1) <= Npcs
                axes(ha(+jj+1));
                imagesc(hist.spkMap_pertrial(:,:,ii*nPlot+jj+1)); 
                yticks(1:Ntrials:Ntrials); yticklabels([1,Ntrials]); ylabel('Trial #');
                xticks([1 15 30]); xticklabels([1 50 100]); xlabel('Position (cm)');
                axis off; title(['Cell ' num2str(ii*nPlot+jj+1)],'fontsize',15);
            end
        end
        if Npcs/nPlot <= 1
            fname_fig = [sdir '/PFmaps/' expsubname '_spk_pertrial_hist'];
        else
            fname_fig = [sdir '/PFmaps/' expsubname '_spk_pertrial_hist_' num2str(ii+1)];
        end
        savefig( fh, fname_fig );
        saveas( fh, fname_fig, 'png' );
        close( fh );
    end 

    for ii=0:Npcs/nPlot
        fh = figure;
        ha = tight_subplot(nRow,nCol,[.01 .01],[.01 .05],[.01 .01]);
        for jj=0:nPlot-1
            if (ii*nPlot+jj+1) <= Npcs
                axes(ha(+jj+1));
                imagesc(hist.normspkMap_pertrial(:,:,ii*nPlot+jj+1)); 
                yticks(1:Ntrials:Ntrials); yticklabels([1,Ntrials]); ylabel('Trial #');
                xticks([1 15 30]); xticklabels([1 50 100]); xlabel('Position (cm)');
                axis off; title(['Cell ' num2str(ii*nPlot+jj+1)],'fontsize',15);
            end
        end
        if Npcs/nPlot <= 1
            fname_fig = [sdir '/PFmaps/' expsubname '_normspk_pertrial_hist'];
        else
            fname_fig = [sdir '/PFmaps/' expsubname '_normspk_pertrial_hist_' num2str(ii+1)];
        end
        savefig( fh, fname_fig );
        saveas( fh, fname_fig, 'png' );
        close( fh );
    end 

    % asd
    [nRow, nCol] = getnRownCol(Npcs_asd);
    nPlot = nRow*nCol;

    Ntrials = size(asd.spkMap_pertrial,1);
    for ii=0:Npcs_asd/nPlot
        fh = figure;
        ha = tight_subplot(nRow,nCol,[.01 .01],[.01 .05],[.01 .01]);
        for jj=0:nPlot-1
            if (ii*nPlot+jj+1) <= Npcs_asd
                axes(ha(+jj+1));
                imagesc(asd.spkMap_pertrial(:,:,ii*nPlot+jj+1)); 
                yticks(1:Ntrials:Ntrials); yticklabels([1,Ntrials]); ylabel('Trial #');
                xticks([1 15 30]); xticklabels([1 50 100]); xlabel('Position (cm)');
                axis off; title(['Cell ' num2str(ii*nPlot+jj+1)],'fontsize',15);
            end
        end
        if Npcs_asd/nPlot <= 1
            fname_fig = [sdir '/PFmaps/' expsubname '_spk_pertrial_asd'];
        else
            fname_fig = [sdir '/PFmaps/' expsubname '_spk_pertrial_asd_' num2str(ii+1)];
        end
        savefig( fh, fname_fig );
        saveas( fh, fname_fig, 'png' );
        close( fh );
    end 

    for ii=0:Npcs_asd/nPlot
        fh = figure;
        ha = tight_subplot(nRow,nCol,[.01 .01],[.01 .05],[.01 .01]);
        for jj=0:nPlot-1
            if (ii*nPlot+jj+1) <= Npcs_asd
                axes(ha(+jj+1));
                imagesc(asd.normspkMap_pertrial(:,:,ii*nPlot+jj+1)); 
                yticks(1:Ntrials:Ntrials); yticklabels([1,Ntrials]); ylabel('Trial #');
                xticks([1 15 30]); xticklabels([1 50 100]); xlabel('Position (cm)');
                axis off; title(['Cell ' num2str(ii*nPlot+jj+1)],'fontsize',15);
            end
        end
        if Npcs_asd/nPlot <= 1
            fname_fig = [sdir '/PFmaps/' expsubname '_normspk_pertrial_asd'];
        else
            fname_fig = [sdir '/PFmaps/' expsubname '_normspk_pertrial_asd_' num2str(ii+1)];
        end
        savefig( fh, fname_fig );
        saveas( fh, fname_fig, 'png' );
        close( fh );
    end 

    % remapping within a session
    if Nepochs > 1
        fh = figure;
        for ei = 1:Nepochs % rows: sorting
            for ej = 1:Nepochs % cols: epochs 
                subplot(Nepochs, Nepochs, (ei-1)*Nepochs + ej); imagesc(hist.normpfMap(hist.sortIdx(:,ei),:,ej)); 
                title(['Epoch ' num2str(ej)]); ylabel(['Epoch' num2str(ei) ' sorting']);
            end
        end
        fname_fig = [sdir '/PFmaps/' expsubname '_remapping_hist'];
        savefig( fh, fname_fig );
        saveas( fh, fname_fig, 'png' );
        close( fh );

        fh = figure;
        for ei = 1:Nepochs % rows: sorting
            for ej = 1:Nepochs % cols: epochs 
                subplot(Nepochs, Nepochs, (ei-1)*Nepochs + ej); imagesc(asd.normpfMap(asd.sortIdx(:,ei),:,ej)); 
                title(['Epoch ' num2str(ej)]); ylabel(['Epoch' num2str(ei) ' sorting']);
            end
        end
        fname_fig = [sdir '/PFmaps/' expsubname '_remapping_asd'];
        savefig( fh, fname_fig );
        saveas( fh, fname_fig, 'png' );
        close( fh );
    end
end

function makeplot_2d(spkMap, activeData, hist, asd)
    Nspk = size(spkMap,3);
    nPlot = 4;
    for e = 1:Nepochs
        for ii=0:(Nspk/nPlot)-1 
            fh = figure; 
            ha = tight_subplot(nPlot,4,[.01 .005],[.01 .07],[.01 .01]);
            for jj=0:3
                if (ii*nPlot+jj) <= Nspk
                    axes(ha(jj*nPlot+1));
                    z = activeData.spikes(spkIdx(ii*nPlot+jj+1),:);
                    hold on; axis off;
                    plot(activeData.x,-activeData.y); plot(activeData.x(z>0),-activeData.y(z>0),'r.','markersize',10);
                    title(['Cell ',num2str(ii*nPlot+jj+1)],'fontsize',15);
                    axes(ha(jj*nPlot+2));
                    imagesc(squeeze(hist.pfMap(:,:,ii*nPlot+jj+1,e))');
                    axis off; colorbar; % caxis([0 0.06]);
                    if Nepochs >1 
                        title(['Epoch ',num2str(e)],'fontsize',15);
                    end
                    axes(ha(jj*nPlot+3)); 
                    imagesc(squeeze(hist.pfMap_sm(:,:,ii*nPlot+jj+1,e))');
                    axis off; colorbar; % caxis([0 0.005]);
                    axes(ha(jj*nPlot+4));
                    imagesc(squeeze(asd.pfMap(:,:,ii*nPlot+jj+1,e))');
                    axis off; colorbar; % caxis([0 0.003]);
                end
            end
            if Nspk/nPlot <= 1
                if Nepochs == 1
                    fname_fig = [sdir '/PFmaps/' expsubname '_PFmaps'];
                else
                    fname_fig = [sdir '/PFmaps/' expsubname '_PFmaps_' num2str(e) 'of' num2str(Nepochs) 'ep' ];
                end
            else
                if Nepochs == 1
                    fname_fig = [sdir '/PFmaps/' expsubname '_PFmaps_' num2str(ii+1)];
                else
                    fname_fig = [sdir '/PFmaps/' expsubname '_PFmaps_' num2str(ii+1) '_' num2str(e) 'of' num2str(Nepochs) 'ep' ];
                end
            end
            savefig( fh, fname_fig );
            saveas( fh, fname_fig, 'png' );
            close( fh );
        end 
    end
end
    
end