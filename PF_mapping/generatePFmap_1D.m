% Written by Ann Go (some parts adapted from Giuseppe's PF_ASD_1d.m)
%
% This function maps place fields
%
% INPUTS:
%   spikes      : spike estimates obtained with oasisAR2
%   imtime      : imaging timestamps
%   trackData   : cell of tracking data with fields x, y, r, phi, w,
%                  speed, time, alpha, TTLout
%   params.
%     fr                    : imaging frame rate [default: 30.9 Hz]
%     PFmap.Nbins           : number of location bins
%     PFmap.Nepochs         : number of epochs for each 4 min video [default: 1]
%     PFmap.Vthr            : speed threshold (mm/s) [default: 20]
%     PFmap.histsmoothFac   : Gaussian smoothing window for histogram
%                               estimation [default: 10]

% OUTPUTS:
%   occMap                  : occupancy map
%   hist., asd.
%     spkMap                : spike map (Ncells rows x Nbins columns)
%     normspkMap
%     infoMap               : information map 
%     pfMap                 : place field map obtained with histogram estimation 
%     pfMap_sm              : (hist only) smoothed version of placeMap 
%     normpfMap             : place field map obtained with histogram estimation 
%     normpfMap_sm          : (hist only) smoothed version of placeMap 
%     spkRaster
%     normspkRaster
%     pcIdx                 : row indices of original spikes corresponding
%                               to place cells
%   downData    : tracking data downsampled to imaging frequency, fields are
%                 x, y, r, phi, speed, t
%   activeData  : downsampled tracking data for when animal was moving, fields are
%                 x, y, r, phi, speed, t, spikes, spikes_pc 

function [ hist, asd, activeData, outData ] = generatePFmap_1D( spikes, trackData, params, dsample )
    
if nargin<4, dsample = false; end

fr = params.fr;
Nposbins = params.PFmap.Nbins;
Nepochs = params.PFmap.Nepochs;
Vthr = params.PFmap.Vthr;
histsmoothFac = params.PFmap.histsmoothFac;
prctile_thr = params.PFmap.prctile_thr;
Ncells = size(spikes,1);

%% Pre-process tracking data
if dsample
    downData = downsample_trackData(trackData, spikes, fr);
    downx = downData.x;
    downy = downData.y;
    downphi = downData.phi;
    downr = downData.r;
    downspeed = downData.speed;
    t = downData.time;
else
    downx = trackData.x;
    downy = trackData.y;
    downphi = trackData.phi;
    downr = trackData.r;
    downspeed = trackData.speed;
    t = trackData.time;
end
dt = mean(diff(t));

% Consider only samples when the mouse is active
activex     = downx(downspeed > Vthr);
activey     = downy(downspeed > Vthr);
activephi   = downphi(downspeed > Vthr);
activespk   = spikes(:,downspeed > Vthr);
activet     = t(downspeed > Vthr);
activespeed = downspeed(downspeed > Vthr);
activer     = downr(downspeed > Vthr);

% Bin phi data
[bin_phi,~] = discretize(activephi,Nposbins);


%% Calculate spike maps per trial
dthr = 10;
for ii = 1:Ncells
    % find the delineations for the video: find t = 0
    idx_file = find(diff(activet) < 0);
    idx_file = [0; idx_file; numel(activet)] +1; 
    p = bin_phi;
    s = activespk(ii,:);
    Ntrial = 1;
    ytick_files = 1;
    
    for jj = 1:numel(idx_file)-1
        % find the delineations per trial (i.e. loop)
        p_tr = p(idx_file(jj):idx_file(jj+1)-1);
        s_tr = s(idx_file(jj):idx_file(jj+1)-1);
        idx_tr = find( abs(diff(p_tr)) > dthr );
        for k = numel(idx_tr):-1:2
            if (idx_tr(k) - idx_tr(k-1)) <= 20 
                idx_tr(k) = 0;
            end
        end
        idx_tr = idx_tr( idx_tr > 0 );
        if numel(idx_tr)==1, idx_tr = [idx_tr; numel(p_tr)]; end
        
        for k = 1:numel(idx_tr)-1
            phi{Ntrial} = p_tr(idx_tr(k)+1:idx_tr(k+1));
            spike{ii}{Ntrial} = s_tr(idx_tr(k)+1:idx_tr(k+1));
            Ntrial = Ntrial + 1;
        end
        
        Ntrials(jj) = numel(idx_tr)-1;
        if jj == numel(idx_file)-1
            ytick_files = [ytick_files; sum(Ntrials(1:jj))];
        else
            ytick_files = [ytick_files; sum(Ntrials(1:jj))+1];
        end
    end
end

for ii = 1:Ncells
    for tr = 1:numel(phi)
        phi_tr = phi{tr};
        spike_tr = spike{ii}{tr};

        for n = 1:Nposbins
            spkRaster{ii}(tr,n) = sum(spike_tr(phi_tr == n));
        end

        normspkRaster{ii}(tr,:) = spkRaster{ii}(tr,:)./max(spkRaster{ii}(tr,:));
        normspkRaster{ii}(isnan(normspkRaster{ii})) = 0;
    end
    meanspkRaster(ii,:) = mean(spkRaster{ii},1);    
    spkPeak(ii) = max(max(spkRaster{ii}));
    spkMean(ii) = mean(mean(spkRaster{ii}));
end

%% Identify place cells by first calculating PF maps for entire session
% (i.e. Nepochs = 1)

% Initialise matrices
spkMap = zeros(Ncells, Nposbins);           % spike map
normspkMap = zeros(Ncells, Nposbins);       % normalised spike map
pfMap = zeros(Ncells, Nposbins);            % place field map
normpfMap = zeros(Ncells, Nposbins);        % normalised place field map
pfMap_sm = zeros(Ncells, Nposbins);         % smoothened place field map
normpfMap_sm = zeros(Ncells, Nposbins);     % smoothened normalised place field map
pfMap_asd = zeros(Ncells, Nposbins);        % place field map for asd
normpfMap_asd = zeros(Ncells, Nposbins);    % normalised place field map for asd
infoMap = zeros(Ncells, 3);              % info values
infoMap_asd = zeros(Ncells,32);          % info values for asd
centroid = zeros(Ncells,1);
centroid_asd = zeros(Ncells,1);
fieldsize = zeros(Ncells,1);
fieldsize_asd = zeros(Ncells,1);

% Calculate PF maps
occMap = histcounts(bin_phi,Nposbins);
for id = 1:Ncells
    z = activespk(id,:);

    % Spike rate maps
    for n = 1:Nposbins
        spkMap(id,n) = sum(z(bin_phi == n));
    end
    normspkMap(id,:) = spkMap(id,:)./max(spkMap(id,:));

    % histogram estimation
    pfMap(id,:) = spkMap(id,:)./(occMap*dt);
    normpfMap(id,:) = pfMap(id,:)./max(pfMap(id,:));
    
    pfMap_sm(id,:) = smoothdata(pfMap(id,:),'gaussian',Nposbins/histsmoothFac);
    normpfMap_sm(id,:) = pfMap_sm(id,:)./max(pfMap_sm(id,:));
    
    [infoMap(id,1), infoMap(id,2), infoMap(id,3)] = infoMeasures(pfMap(id,:),occMap,0);
    [~,c,fs] = findpeaks(normpfMap_sm(id,:),'WidthReference','halfheight','SortStr','descend');
    if ~isempty(c), centroid(id) = c(1); else, centroid(id) = NaN; end
    if ~isempty(fs), fieldsize(id) = fs(1)*103/Nposbins; else, fieldsize(id) = NaN; end
    
    % ASD estimation
    [pfMap_asd(id,:),~] = runASD_1d(bin_phi,z',Nposbins);
    normpfMap_asd(id,:) = pfMap_asd(id,:)./max(pfMap_asd(id,:));
    [infoMap_asd(id,1), infoMap_asd(id,2), infoMap_asd(id,3)] =...
        infoMeasures(pfMap_asd(id,:)',ones(Nposbins,1),0);
    [~,c,fs] = findpeaks(normpfMap_asd(id,:),'WidthReference','halfheight','SortStr','descend');
    if ~isempty(c), centroid_asd(id) = c(1); else, centroid_asd(id) = NaN;  end
    if ~isempty(fs), fieldsize_asd(id) = fs(1)*103/Nposbins; else, fieldsize_asd(id) = NaN; end
end

% Identify place cells. The cells are sorted in descending order of info
% content
[hist.pcIdx_MI, hist.pcIdx_SIsec, hist.pcIdx_SIspk, hist.nonpcIdx_MI, hist.nonpcIdx_SIsec, hist.nonpcIdx_SIspk] ...
    = identifyPCs( spkRaster, spkPeak, bin_phi, activespk, infoMap, Nposbins, prctile_thr);
[asd.pcIdx_MI, asd.pcIdx_SIsec, asd.pcIdx_SIspk, asd.nonpcIdx_MI, asd.nonpcIdx_SIsec, asd.nonpcIdx_SIspk] ...
    = identifyPCs( spkRaster, spkPeak, bin_phi, activespk, infoMap_asd, Nposbins, prctile_thr);


%% Finalise place field maps, recalculate if Nepochs > 1
if Nepochs > 1
    % Initialise matrices
    occMap = zeros(Nepochs, Nposbins);                         
    spkMap = zeros(Ncells, Nposbins, Nepochs);
    normspkMap = zeros(Ncells, Nposbins, Nepochs);   
    pfMap = zeros(Ncells, Nposbins, Nepochs);               
    pfMap_sm = zeros(Ncells, Nposbins, Nepochs);            
    normpfMap = zeros(Ncells, Nposbins, Nepochs);        
    normpfMap_sm = zeros(Ncells, Nposbins, Nepochs);     
    infoMap = zeros(Ncells, 3, Nepochs); 
    infoMap_asd = zeros(Ncells, 3, Nepochs);
    centroid = zeros(Ncells, Nepochs);
    centroid_asd = zeros(Ncells, Nepochs);
    fieldsize = zeros(Ncells, Nepochs);
    fieldsize_asd = zeros(Ncells, Nepochs);
    bin_phi_e = zeros(Nepochs, Nposbins);
    
    % Calculate PF maps
    e_bound = round( linspace(1,size(activespk,2),Nepochs+1) );
    for id = 1:Ncells
        z = activespk(id,:);

        % separate exploration in smaller intervals
        for e = 1:Nepochs
            bin_phi_e(:,e) = bin_phi(e_bound(e):e_bound(e+1));
            spike_e = z(e_bound(e):e_bound(e+1));

            % Occupancy and spike rate maps
            occMap(e,:) = histcounts(bin_phi_e(:,e),Nposbins);
            for n = 1:Nposbins
                spkMap(id,n,e) = sum(spike_e(bin_phi_e(:,e) == n));
            end
            normspkMap(id,:,e) = spkMap(id,:,e)./max(spkMap(id,:,e));
            
            % histogram estimation
            pfMap(id,:,e) = spkMap(id,:,e)./(occMap(e,:)*dt);
            pfMap(isnan(pfMap)) = 0;
            pfMap_sm(id,:,e) = smoothdata(pfMap(id,:,e),'gaussian',Nposbins/histsmoothFac);

            normpfMap(id,:,e) = pfMap(id,:,e)./max(pfMap(id,:,e));
            normpfMap_sm(id,:,e) = pfMap_sm(id,:,e)./max(pfMap_sm(id,:,e));
            
            [infoMap(id,1,e), infoMap(id,2,e), infoMap(id,3,e)] = infoMeasures(pfMap(id,:,e),occMap(e,:),0);
            [~,c,fs] = findpeaks(normpfMap(id,:,e),'WidthReference','halfheight','SortStr','descend');
            if ~isempty(c), centroid(id,e) = c(1); else, centroid(id,e) = NaN; end
            if ~isempty(fs), fieldsize(id,e) = fs(1); else, fieldsize(id,e) = NaN; end
            
            % asd estimation
            [pfMap_asd(id,:,e),~] = runASD_1d(bin_phi_e(:,e),(spike_e)',Nposbins);
            normpfMap_asd(id,:,e) = pfMap_asd(id,:,e)./max(pfMap_asd(id,:,e));
            [infoMap_asd(id,1,e), infoMap_asd(id,2,e), infoMap_asd(id,3,e)] = ...
                infoMeasures(squeeze(pfMap_asd(id,:,e))',ones(Nposbins,1),0);
            [~,c,fs] = findpeaks(normpfMap_asd(id,:,e),'WidthReference','halfheight','SortStr','descend');
            if ~isempty(c), centroid_asd(id,e) = c(1); else, centroid_asd(id,e) = NaN; end
            if ~isempty(fs), fieldsize_asd(id,e) = fs(1); else, fieldsize_asd(id,e) = NaN; end
        end
    end
end

% histogram estimation
if ~isempty(hist.pcIdx_MI)
    hist.spkRaster_MI_pc = spkRaster(hist.pcIdx_MI);
    hist.normspkRaster_MI_pc = normspkRaster(hist.pcIdx_MI);
    hist.meanspkRaster_MI = meanspkRaster(hist.pcIdx_MI);
    hist.spkMean_MI = spkMean(hist.pcIdx_MI);
    hist.spkPeak_MI = spkPeak(hist.pcIdx_MI);
    
    hist.spkMap_MI = spkMap(hist.pcIdx_MI,:,:);
    hist.normspkMap_MI = normspkMap(hist.pcIdx_MI,:,:);
    hist.pfMap_MI = pfMap(hist.pcIdx_MI,:,:);
    hist.normpfMap_MI = normpfMap(hist.pcIdx_MI,:,:);
    hist.pfMap_MI_sm = pfMap_sm(hist.pcIdx_MI,:,:);
    hist.normpfMap_MI_sm = normpfMap_sm(hist.pcIdx_MI,:,:);
    hist.infoMap_MI = infoMap(hist.pcIdx_MI,1,:);
    hist.centroid_MI = centroid(hist.pcIdx_MI,:);
    hist.fieldsize_MI = fieldsize(hist.pcIdx_MI,:);
end
if ~isempty(hist.nonpcIdx_MI)
    hist.spkRaster_MI_nonpc = spkRaster(hist.nonpcIdx_MI);
    hist.normspkRaster_MI_nonpc = normspkRaster(hist.nonpcIdx_MI);
end

if ~isempty(hist.pcIdx_SIsec)
    hist.spkRaster_SIsec_pc = spkRaster(hist.pcIdx_SIsec);
    hist.normspkRaster_SIsec_pc = normspkRaster(hist.pcIdx_SIsec);
    hist.meanspkRaster_SIsec = meanspkRaster(hist.pcIdx_SIsec);
    hist.spkMean_SIsec = spkMean(hist.pcIdx_SIsec);
    hist.spkPeak_SIsec = spkPeak(hist.pcIdx_SIsec);
    
    hist.spkMap_SIsec = spkMap(hist.pcIdx_SIsec,:,:);
    hist.normspkMap_SIsec = normspkMap(hist.pcIdx_SIsec,:,:);
    hist.pfMap_SIsec = pfMap(hist.pcIdx_SIsec,:,:);
    hist.normpfMap_SIsec = normpfMap(hist.pcIdx_SIsec,:,:);
    hist.pfMap_SIsec_sm = pfMap_sm(hist.pcIdx_SIsec,:,:);
    hist.normpfMap_SIsec_sm = normpfMap_sm(hist.pcIdx_SIsec,:,:);
    hist.infoMap_SIsec = infoMap(hist.pcIdx_SIsec,2,:);
    hist.centroid_SIsec = centroid(hist.pcIdx_SIsec,:);
    hist.fieldsize_SIsec = fieldsize(hist.pcIdx_SIsec,:);
end
if ~isempty(hist.nonpcIdx_SIsec)
    hist.spkRaster_SIsec_nonpc = spkRaster(hist.nonpcIdx_SIsec);
    hist.normspkRaster_SIsec_nonpc = normspkRaster(hist.nonpcIdx_SIsec);
end

if ~isempty(hist.pcIdx_SIspk)
    hist.spkRaster_SIspk_pc = spkRaster(hist.pcIdx_SIspk);
    hist.normspkRaster_SIspk_pc = normspkRaster(hist.pcIdx_SIspk);
    hist.meanspkRaster_SIspk = meanspkRaster(hist.pcIdx_SIspk);
    hist.spkMean_SIspk = spkMean(hist.pcIdx_SIspk);
    hist.spkPeak_SIspk = spkPeak(hist.pcIdx_SIspk);
    
    hist.spkMap_SIspk = spkMap(hist.pcIdx_SIspk,:,:);
    hist.normspkMap_SIspk = normspkMap(hist.pcIdx_SIspk,:,:);
    hist.pfMap_SIspk = pfMap(hist.pcIdx_SIspk,:,:);
    hist.normpfMap_SIspk = normpfMap(hist.pcIdx_SIspk,:,:);
    hist.pfMap_SIspk_sm = pfMap_sm(hist.pcIdx_SIspk,:,:);
    hist.normpfMap_SIspk_sm = normpfMap_sm(hist.pcIdx_SIspk,:,:);
    hist.infoMap_SIspk = infoMap(hist.pcIdx_SIspk,3,:);
    hist.centroid_SIspk = centroid(hist.pcIdx_SIspk,:);
    hist.fieldsize_SIspk = fieldsize(hist.pcIdx_SIspk,:);
end
if ~isempty(hist.nonpcIdx_SIspk)
    hist.spkRaster_SIspk_nonpc = spkRaster(hist.nonpcIdx_SIspk);
    hist.normspkRaster_SIspk_nonpc = normspkRaster(hist.nonpcIdx_SIspk);
end

%asd
if ~isempty(asd.pcIdx_MI)
    asd.spkRaster_MI_pc = spkRaster(asd.pcIdx_MI);
    asd.normspkRaster_MI_pc = normspkRaster(asd.pcIdx_MI);
    asd.meanspkRaster_MI = meanspkRaster(asd.pcIdx_MI);
    asd.spkMean_MI = spkMean(asd.pcIdx_MI);
    asd.spkPeak_MI = spkPeak(asd.pcIdx_MI);
    
    asd.spkMap_MI = spkMap(asd.pcIdx_MI,:,:);
    asd.normspkMap_MI = normspkMap(asd.pcIdx_MI,:,:);
    asd.pfMap_MI = pfMap_asd(asd.pcIdx_MI,:,:);
    asd.normpfMap_MI = normpfMap_asd(asd.pcIdx_MI,:,:);
    asd.infoMap_MI = infoMap_asd(asd.pcIdx_MI,1,:);
    asd.centroid_MI = centroid_asd(asd.pcIdx_MI,:);
    asd.fieldsize_MI = fieldsize_asd(asd.pcIdx_MI,:);
end
if ~isempty(asd.nonpcIdx_MI)
    asd.spkRaster_MI_nonpc = spkRaster(asd.nonpcIdx_MI);
    asd.normspkRaster_MI_nonpc = normspkRaster(asd.nonpcIdx_MI);
end

if ~isempty(asd.pcIdx_SIsec)
    asd.spkRaster_SIsec_pc = spkRaster(asd.pcIdx_SIsec);
    asd.normspkRaster_SIsec_pc = normspkRaster(asd.pcIdx_SIsec);
    asd.meanspkRaster_SIsec = meanspkRaster(asd.pcIdx_SIsec);
    asd.spkMean_SIsec = spkMean(asd.pcIdx_SIsec);
    asd.spkPeak_SIsec = spkPeak(asd.pcIdx_SIsec);
    
    asd.spkMap_SIsec = spkMap(asd.pcIdx_SIsec,:,:);
    asd.normspkMap_SIsec = normspkMap(asd.pcIdx_SIsec,:,:);
    asd.pfMap_SIsec = pfMap_asd(asd.pcIdx_SIsec,:,:);
    asd.normpfMap_SIsec = normpfMap_asd(asd.pcIdx_SIsec,:,:);
    asd.infoMap_SIsec = infoMap_asd(asd.pcIdx_SIsec,2,:);
    asd.centroid_SIsec = centroid_asd(asd.pcIdx_SIsec,:);
    asd.fieldsize_SIsec = fieldsize_asd(asd.pcIdx_SIsec,:);
end
if ~isempty(asd.nonpcIdx_SIsec)
    asd.spkRaster_SIsec_nonpc = spkRaster(asd.nonpcIdx_SIsec);
    asd.normspkRaster_SIsec_nonpc = normspkRaster(asd.nonpcIdx_SIsec);
end

if ~isempty(asd.pcIdx_SIspk)
    asd.spkRaster_SIspk_pc = spkRaster(asd.pcIdx_SIspk);
    asd.normspkRaster_SIspk_pc = normspkRaster(asd.pcIdx_SIspk);
    asd.meanspkRaster_SIspk = meanspkRaster(asd.pcIdx_SIspk);
    asd.spkMean_SIspk = spkMean(asd.pcIdx_SIspk);
    asd.spkPeak_SIspk = spkPeak(asd.pcIdx_SIspk);
    
    asd.spkMap_SIspk = spkMap(asd.pcIdx_SIspk,:,:);
    asd.normspkMap_SIspk = normspkMap(asd.pcIdx_SIspk,:,:);
    asd.pfMap_SIspk = pfMap_asd(asd.pcIdx_SIspk,:,:);
    asd.normpfMap_SIspk = normpfMap_asd(asd.pcIdx_SIspk,:,:);
    asd.infoMap_SIspk = infoMap_asd(asd.pcIdx_SIspk,3,:);
    asd.centroid_SIspk = centroid_asd(asd.pcIdx_SIspk,:);
    asd.fieldsize_SIspk = fieldsize_asd(asd.pcIdx_SIspk,:);
end
if ~isempty(asd.nonpcIdx_SIspk)
    asd.spkRaster_SIspk_nonpc = spkRaster(asd.nonpcIdx_SIspk);
    asd.normspkRaster_SIspk_nonpc = normspkRaster(asd.nonpcIdx_SIspk);
end

% Outputs
activeData.x = activex;
activeData.y = activey;
activeData.r = activer;
activeData.phi = activephi;
activeData.speed = activespeed;
activeData.t = activet;
activeData.spikes = activespk;

outData.occMap = occMap;
outData.spkRaster = spkRaster;
outData.normspkRaster = normspkRaster;
outData.ytick_files = ytick_files;
outData.meanspkRaster = meanspkRaster;
outData.spkMean = spkMean;
outData.spkPeak = spkPeak;
if exist('bin_phi_e','var')
    outData.bin_phi = bin_phi_e;
else
    outData.bin_phi = bin_phi;
end

end


