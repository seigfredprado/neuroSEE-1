% Written by Ann Go (some parts adapted from Giuseppe's PF_ASD_1d.m)
%
% This function maps place fields
%
% INPUTS:
%   spikes      : spike estimates obtained with oasisAR2
%   imtime      : imaging timestamps
%   downTrackdata   : cell of tracking data with fields x, y, r, phi, w,
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

function [ hist, asd, activeData, PFdata ] = generatePFmap_1d( spikes, downTrackdata, params, doasd )
    
if nargin < 4, doasd = true; end
Nbins = params.PFmap.Nbins;
Nepochs = params.PFmap.Nepochs;
Vthr = params.PFmap.Vthr;
histsmoothWin = params.PFmap.histsmoothWin;
prctile_thr = params.PFmap.prctile_thr;
Nlaps_thr = params.PFmap.Nlaps_thr;
Ncells = size(spikes,1);

% Input data
x = downTrackdata.x;
y = downTrackdata.y;
phi = downTrackdata.phi;
r = downTrackdata.r;
speed = downTrackdata.speed;
t = downTrackdata.time;
ind = find(abs(diff(t))>200);
    if numel(ind)>1
        dt = mean(diff(t(1:ind(1))));
    else
        dt = mean(diff(t));
    end

% Consider only samples when the mouse is active
activex     = x(speed > Vthr);
activey     = y(speed > Vthr);
activephi   = phi(speed > Vthr);
activespk   = spikes(:,speed > Vthr);
activet     = t(speed > Vthr);
activespeed = speed(speed > Vthr);
activer     = r(speed > Vthr);
clear x y phi r speed t

% Bin phi data
[bin_phi,~] = discretize(activephi,Nbins);


%% ALL CELLS
% Calculate spike maps per trial
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
        idx_tr = find( p_tr == p_tr(1) );
        for k = numel(idx_tr):-1:2
            if (idx_tr(k) - idx_tr(k-1)) <= Nbins 
                idx_tr(k) = 0;
            end
        end
        idx_tr = idx_tr( idx_tr > 0 );
        Ntrials(jj) = numel(idx_tr)-1;
        if Ntrials(jj) > 0
            for k = 1:numel(idx_tr)-1
                phi_trials{Ntrial} = p_tr(idx_tr(k)+1:idx_tr(k+1));
                spike_trials{ii}{Ntrial} = s_tr(idx_tr(k)+1:idx_tr(k+1));
                Ntrial = Ntrial + 1;
            end

            if jj == numel(idx_file)-1
                ytick_files = [ytick_files; sum(Ntrials(1:jj))];
            else
                ytick_files = [ytick_files; sum(Ntrials(1:jj))+1];
            end
        end
    end
end

meanspkRaster = zeros(Ncells,Nbins);
spkPeak = zeros(Ncells);
spkMean = zeros(Ncells);
for ii = 1:Ncells
    for tr = 1:numel(phi)
        phi_tr = phi_trials{tr};
        spike_tr = spike_trials{ii}{tr};

        for n = 1:Nbins
            spkRaster{ii}(tr,n) = sum(spike_tr(phi_tr == n));
        end

        normspkRaster{ii}(tr,:) = spkRaster{ii}(tr,:)./max(spkRaster{ii}(tr,:));
        normspkRaster{ii}(isnan(normspkRaster{ii})) = 0;
    end
    meanspkRaster(ii,:) = mean(spkRaster{ii},1);    
    spkPeak(ii) = max(max(spkRaster{ii}));
    spkMean(ii) = mean(mean(spkRaster{ii}));
end

% Identify place cells by first calculating PF maps for entire session
% (i.e. Nepochs = 1)

% Initialise matrices
spkMap = zeros(Ncells, Nbins);              % spike map
normspkMap = zeros(Ncells, Nbins);          % normalised spike map

hist.rMap = zeros(Ncells, Nbins);          % place field map
hist.rMap_sm = zeros(Ncells, Nbins);       % smoothened place field map
hist.normrMap_sm = zeros(Ncells, Nbins);   % smoothened normalised place field map
hist.infoMap = zeros(Ncells,2);             % info values
hist.pfLoc = zeros(Ncells,1);
hist.fieldSize = zeros(Ncells,1);

if doasd
    asd.rMap = zeros(Ncells, Nbins);           % place field map for asd
    asd.rMap = zeros(Ncells, Nbins);       % normalised place field map for asd
    asd.infoMap = zeros(Ncells,2);              % info values
    asd.pfLoc = zeros(Ncells,1);
    asd.fieldSize = zeros(Ncells,1);
end

% Calculate PF maps
occMap = histcounts(bin_phi,Nbins);
for id = 1:Ncells
    z = activespk(id,:);

    % Spike rate maps
    for n = 1:Nbins
        spkMap(id,n) = sum(z(bin_phi == n));
    end
    normspkMap(id,:) = spkMap(id,:)./max(spkMap(id,:));

    % histogram estimation
    hist.rMap(id,:) = spkMap(id,:)./(occMap*dt);    
    hist.rMap_sm(id,:) = circularSmooth(hist.rMap(id,:),histsmoothWin);
    hist.normrMap_sm(id,:) = hist.rMap_sm(id,:)./max(hist.rMap_sm(id,:));
    [hist.infoMap(id,1), hist.infoMap(id,2)] = infoMeasures(hist.rMap(id,:),occMap,0);
    
    if doasd
        % ASD estimation
        [asd.rMap(id,:),~] = runASD_1d(bin_phi,z',Nbins);
        asd.normrMap(id,:) = asd.rMap(id,:)./max(asd.rMap(id,:));
        [asd.infoMap(id,1), asd.infoMap(id,2)] = infoMeasures(asd.rMap(id,:)',ones(Nbins,1),0);
    end
end

% Find location preference and field size
[~, hist.pfLoc] = prefLoc( hist.rMap_sm );
hist.fieldSize = fieldSize( hist.rMap_sm );

if doasd
    [~, asd.pfLoc] = prefLoc( asd.rMap );
    asd.fieldSize = fieldSize( asd.rMap );
end


%% PLACE CELLS
% Identify place cells. The cells are sorted in descending order of info content
[hist.SIsec.pcIdx, hist.SIspk.pcIdx, hist.SIsec.nonpcIdx, hist.SIspk.nonpcIdx] ...
    = identifyPCs_1d( spkRaster, spkPeak, bin_phi, activespk, hist.infoMap, Nbins, prctile_thr, Nlaps_thr, 1000);
if doasd
    [asd.SIsec.pcIdx, asd.SIspk.pcIdx, asd.SIsec.nonpcIdx, asd.SIspk.nonpcIdx] ...
    = identifyPCs_1d( spkRaster, spkPeak, bin_phi, activespk, asd.infoMap, Nbins, prctile_thr, Nlaps_thr, 1000, 'asd');
end


%% Finalise place field maps, recalculate if Nepochs > 1
if Nepochs > 1
    % Initialise matrices
    occMap = zeros(Nepochs, Nbins);                         
    spkMap = zeros(Ncells, Nbins, Nepochs);
    normspkMap = zeros(Ncells, Nbins, Nepochs);   
    bin_phi_e = zeros(Nepochs, Nbins);
    
    hist.rMap = zeros(Ncells, Nbins, Nepochs);               
    hist.rMap_sm = zeros(Ncells, Nbins, Nepochs);            
    hist.normrMap_sm = zeros(Ncells, Nbins, Nepochs);     
    hist.infoMap = zeros(Ncells, 2, Nepochs); 
    hist.pfLoc = zeros(Ncells, Nepochs);
    hist.fieldSize = zeros(Ncells, Nepochs);
    
    if doasd
        asd.rMap = zeros(Ncells, Nbins, Nepochs);               
        asd.rMap_sm = zeros(Ncells, Nbins, Nepochs);            
        asd.normrMap_sm = zeros(Ncells, Nbins, Nepochs);     
        asd.infoMap = zeros(Ncells, 2, Nepochs); 
        asd.pfLoc = zeros(Ncells, Nepochs);
        asd.fieldSize = zeros(Ncells, Nepochs);
    end
    
    
    % Calculate PF maps
    e_bound = round( linspace(1,size(activespk,2),Nepochs+1) );
    for id = 1:Ncells
        z = activespk(id,:);

        % separate exploration in smaller intervals
        for e = 1:Nepochs
            bin_phi_e(:,e) = bin_phi(e_bound(e):e_bound(e+1));
            spike_e = z(e_bound(e):e_bound(e+1));

            % Occupancy and spike rate maps
            occMap(e,:) = histcounts(bin_phi_e(:,e),Nbins);
            for n = 1:Nbins
                spkMap(id,n,e) = sum(spike_e(bin_phi_e(:,e) == n));
            end
            normspkMap(id,:,e) = spkMap(id,:,e)./max(spkMap(id,:,e));
            
            % histogram estimation
            hist.rMap(id,:,e) = spkMap(id,:,e)./(occMap(e,:)*dt);
            hist.rMap(isnan(hist.rMap)) = 0;
            hist.rMap_sm(id,:,e) = circularSmooth(hist.rMap(id,:,e),histsmoothWin);
            hist.normrMap_sm(id,:,e) = hist.rMap_sm(id,:,e)./max(hist.rMap_sm(id,:,e));
            [hist.infoMap(id,1,e), hist.infoMap(id,2,e)] = infoMeasures(hist.rMap_sm(id,:,e),occMap(e,:),0);
            [~, hist.pfLoc(id,e)] = prefLoc( hist.rMap_sm(id,:,e) );
            hist.fieldSize(id,e) = fieldSize( hist.rMap_sm(id,:,e) );
            
            if doasd
                % asd estimation
                [asd.rMap(id,:,e),~] = runASD_1d(bin_phi_e(:,e),(spike_e)',Nbins);
                asd.normrMap(id,:,e) = asd.rMap(id,:,e)./max(asd.rMap(id,:,e));
                [asd.infoMap(id,1,e), asd.infoMap(id,2,e)] = infoMeasures(squeeze(asd.rMap(id,:,e))',ones(Nbins,1),0);
                [~, asd.pfLoc(id,e)] = prefLoc( asd.rMap(id,:,e) );
                asd.fieldSize(id,e) = fieldSize( asd.rMap(id,:,e) );
            end

        end
    end
end

% histogram estimation
if ~isempty(hist.SIsec.pcIdx)
    hist.SIsec.spkRaster_pc = spkRaster(hist.SIsec.pcIdx);
    hist.SIsec.normspkRaster_pc = normspkRaster(hist.SIsec.pcIdx);
    hist.SIsec.meanspkRaster = meanspkRaster(hist.SIsec.pcIdx);
    hist.SIsec.spkMean = spkMean(hist.SIsec.pcIdx);
    hist.SIsec.spkPeak = spkPeak(hist.SIsec.pcIdx);
    
    hist.SIsec.spkMap = spkMap(hist.SIsec.pcIdx,:,:);
    hist.SIsec.normspkMap = normspkMap(hist.SIsec.pcIdx,:,:);
    hist.SIsec.pfMap = hist.rMap(hist.SIsec.pcIdx,:,:);
    hist.SIsec.pfMap_sm = hist.rMap_sm(hist.SIsec.pcIdx,:,:);
    hist.SIsec.normpfMap_sm = hist.normrMap_sm(hist.SIsec.pcIdx,:,:);
    hist.SIsec.infoMap = hist.infoMap(hist.SIsec.pcIdx,1,:);
    hist.SIsec.pfLoc = hist.pfLoc(hist.SIsec.pcIdx,:);
    hist.SIsec.pfSize = hist.fieldSize(hist.SIsec.pcIdx,:);
end
if ~isempty(hist.SIsec.nonpcIdx)
    hist.SIsec.spkRaster_nonpc = spkRaster(hist.SIsec.nonpcIdx);
    hist.SIsec.normspkRaster_nonpc = normspkRaster(hist.SIsec.nonpcIdx);
end

if ~isempty(hist.SIspk.pcIdx)
    hist.SIspk.spkRaster_pc = spkRaster(hist.SIspk.pcIdx);
    hist.SIspk.normspkRaster_pc = normspkRaster(hist.SIspk.pcIdx);
    hist.SIspk.meanspkRaster = meanspkRaster(hist.SIspk.pcIdx);
    hist.SIspk.spkMean = spkMean(hist.SIspk.pcIdx);
    hist.SIspk.spkPeak = spkPeak(hist.SIspk.pcIdx);
    
    hist.SIspk.spkMap = spkMap(hist.SIspk.pcIdx,:,:);
    hist.SIspk.normspkMap = normspkMap(hist.SIspk.pcIdx,:,:);
    hist.SIspk.pfMap = hist.rMap(hist.SIspk.pcIdx,:,:);
    hist.SIspk.pfMap_sm = hist.rMap_sm(hist.SIspk.pcIdx,:,:);
    hist.SIspk.normpfMap_sm = hist.normrMap_sm(hist.SIspk.pcIdx,:,:);
    hist.SIspk.infoMap = hist.infoMap(hist.SIspk.pcIdx,2,:);
    hist.SIspk.pfLoc = hist.pfLoc(hist.SIspk.pcIdx,:);
    hist.SIspk.pfSize = hist.fieldSize(hist.SIspk.pcIdx,:);
end
if ~isempty(hist.SIspk.nonpcIdx)
    hist.SIspk.spkRaster_nonpc = spkRaster(hist.SIspk.nonpcIdx);
    hist.SIspk.normspkRaster_nonpc = normspkRaster(hist.SIspk.nonpcIdx);
end

if doasd
    %asd
    if ~isempty(asd.SIsec.pcIdx)
        asd.SIsec.spkRaster_pc = spkRaster(asd.SIsec.pcIdx);
        asd.SIsec.normspkRaster_pc = normspkRaster(asd.SIsec.pcIdx);
        asd.SIsec.meanspkRaster = meanspkRaster(asd.SIsec.pcIdx);
        asd.SIsec.spkMean = spkMean(asd.SIsec.pcIdx);
        asd.SIsec.spkPeak = spkPeak(asd.SIsec.pcIdx);

        asd.SIsec.spkMap = spkMap(asd.SIsec.pcIdx,:,:);
        asd.SIsec.normspkMap = normspkMap(asd.SIsec.pcIdx,:,:);
        asd.SIsec.pfMap = asd.rMap(asd.SIsec.pcIdx,:,:);
        asd.SIsec.normpfMap = asd.normrMap(asd.SIsec.pcIdx,:,:);
        asd.SIsec.infoMap = asd.infoMap(asd.SIsec.pcIdx,1,:);
        asd.SIsec.pfLoc = asd.pfLoc(asd.SIsec.pcIdx,:);
        asd.SIsec.pfSize = asd.fieldSize(asd.SIsec.pcIdx,:);
    end
    if ~isempty(asd.SIsec.nonpcIdx)
        asd.SIsec.spkRaster_nonpc = spkRaster(asd.SIsec.nonpcIdx);
        asd.SIsec.normspkRaster_nonpc = normspkRaster(asd.SIsec.nonpcIdx);
    end

    if ~isempty(asd.SIspk.pcIdx)
        asd.SIspk.spkRaster_pc = spkRaster(asd.SIspk.pcIdx);
        asd.SIspk.normspkRaster_pc = normspkRaster(asd.SIspk.pcIdx);
        asd.SIspk.meanspkRaster = meanspkRaster(asd.SIspk.pcIdx);
        asd.SIspk.spkMean = spkMean(asd.SIspk.pcIdx);
        asd.SIspk.spkPeak = spkPeak(asd.SIspk.pcIdx);

        asd.SIspk.spkMap = spkMap(asd.SIspk.pcIdx,:,:);
        asd.SIspk.normspkMap = normspkMap(asd.SIspk.pcIdx,:,:);
        asd.SIspk.pfMap = asd.rMap(asd.SIspk.pcIdx,:,:);
        asd.SIspk.normpfMap = asd.normrMap(asd.SIspk.pcIdx,:,:);
        asd.SIspk.infoMap = asd.infoMap(asd.SIspk.pcIdx,2,:);
        asd.SIspk.pfLoc = asd.pfLoc(asd.SIspk.pcIdx,:);
        asd.SIspk.pfSize = asd.fieldSize(asd.SIspk.pcIdx,:);
    end
    if ~isempty(asd.SIspk.nonpcIdx)
        asd.SIspk.spkRaster_nonpc = spkRaster(asd.SIspk.nonpcIdx);
        asd.SIspk.normspkRaster_nonpc = normspkRaster(asd.SIspk.nonpcIdx);
    end
end

%% Sort place field maps
for en = 1:Nepochs
    if ~isempty(hist.SIsec.pcIdx)
        [ ~, hist.SIsec.sortIdx(:,en) ] = sort( hist.SIsec.pfLoc(:,en) );
        hist.SIsec.sort_pfMap(:,:,en) = hist.SIsec.pfMap(hist.SIsec.sortIdx(:,en),:,en);
        hist.SIsec.sort_pfMap_sm(:,:,en) = hist.SIsec.pfMap_sm(hist.SIsec.sortIdx(:,en),:,en);
        hist.SIsec.sort_normpfMap_sm(:,:,en) = hist.SIsec.normpfMap_sm(hist.SIsec.sortIdx(:,en),:,en);
    end

    if ~isempty(hist.SIspk.pcIdx)
        [ ~, hist.SIspk.sortIdx(:,en) ] = sort( hist.SIspk.pfLoc(:,en) );
        hist.SIspk.sort_pfMap(:,:,en) = hist.SIspk.pfMap(hist.SIspk.sortIdx(:,en),:,en);
        hist.SIspk.sort_pfMap_sm(:,:,en) = hist.SIspk.pfMap_sm(hist.SIspk.sortIdx(:,en),:,en);
        hist.SIspk.sort_normpfMap_sm(:,:,en) = hist.SIspk.normpfMap_sm(hist.SIspk.sortIdx(:,en),:,en);
    end

    if doasd
        if ~isempty(asd.SIsec.pcIdx)
            [ ~, asd.SIsec.sortIdx(:,en) ] = sort( asd.SIsec.pfLoc(:,en) );
            asd.SIsec.sort_pfMap(:,:,en) = asd.SIsec.pfMap(asd.SIsec.sortIdx(:,en),:,en);
            asd.SIsec.sort_normpfMap(:,:,en) = asd.SIsec.normpfMap(asd.SIsec.sortIdx(:,en),:,en);
        end

        if ~isempty(asd.SIspk.pcIdx)
            [ ~, asd.SIspk.sortIdx(:,en) ] = sort( asd.SIspk.pfLoc(:,en) );
            asd.SIspk.sort_pfMap(:,:,en) = asd.SIspk.pfMap(asd.SIspk.sortIdx(:,en),:,en);
            asd.SIspk.sort_normpfMap(:,:,en) = asd.SIspk.normpfMap(asd.SIspk.sortIdx(:,en),:,en);
        end
    end
end


%% Outputs
activeData.x = activex;
activeData.y = activey;
activeData.r = activer;
activeData.phi = activephi;
activeData.speed = activespeed;
activeData.t = activet;
activeData.spikes = activespk;

PFdata.occMap = occMap;
PFdata.spkRaster = spkRaster;
PFdata.phi_trials = phi_trials;
PFdata.spike_trials = spike_trials;
PFdata.normspkRaster = normspkRaster;
PFdata.ytick_files = ytick_files;
PFdata.meanspkRaster = meanspkRaster;
PFdata.spkMean = spkMean;
PFdata.spkPeak = spkPeak;
if exist('bin_phi_e','var')
    PFdata.bin_phi = bin_phi_e;
else
    PFdata.bin_phi = bin_phi;
end

if ~doasd, asd = []; end

end


