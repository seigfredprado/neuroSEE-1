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

function [ hist, asd, PFdata, varargout ] = generatePFmap_1d( spikes, downTrackdata, params )
if nargin<3, params = neuroSEE_setparams(); end

doasd = params.methods.doasd; 
fr = params.PFmap.fr;
Nrand = params.PFmap.Nrand;
Nbins = params.PFmap.Nbins;
Nepochs = params.PFmap.Nepochs;
Vthr = params.PFmap.Vthr;
histsmoothWin = params.PFmap.histsmoothWin;
prctile_thr = params.PFmap.prctile_thr;
pfactivet_thr = params.PFmap.pfactivet_thr;
activetrials_thr = params.PFmap.activetrials_thr;

% Input data
x = downTrackdata.x;
y = downTrackdata.y;
phi = downTrackdata.phi;
r = downTrackdata.r;
speed = downTrackdata.speed;
t = downTrackdata.time;

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


%% ALL CELLS: calculate PF data for entire duration (one epoch)
[PFdata, hist, asd] = calcPFdata_1d(bin_phi, activephi, activespk, activet, Nbins, histsmoothWin, fr, doasd);
% PFdata is a structure with the following fields
%   phi_trials, spk_trials, bintime_trials, bintime
%   spkRaster, normspkRaster, activetrials
%   spk_rate, spk_amplrate, bin_activity
%   occMap, spkMap, normspkMap

% hist and asd are structures with the following fields
%   rMap, rMap_sm (hist only), normrMap_sm (hist only)
%   infoMap, pfLoc, fieldSize, pfBins


%% Identify PLACE CELLS
% Cells are sorted in descending order of info content
[hist.SIsec.pcIdx, hist.SIspk.pcIdx, hist.SIsec.nonpcIdx, hist.SIspk.nonpcIdx] = identifyPCs_1d( ...
    bin_phi, activespk, hist.infoMap, hist.pf_activet, PFdata.activetrials, prctile_thr, pfactivet_thr, activetrials_thr, Nrand );
if doasd
    [asd.SIsec.pcIdx, asd.SIspk.pcIdx, asd.SIsec.nonpcIdx, asd.SIspk.nonpcIdx] = identifyPCs_1d( ...
    bin_phi, activespk, hist.infoMap, hist.pf_activet, PFdata.activetrials, prctile_thr, pfactivet_thr, activetrials_thr, Nrand, 'asd');
end

% sort pf maps
hist.SIsec = sortPFmaps(hist.rateMap, hist.rateMap_sm, normrateMap_sm, hist.SIsec);
hist.SIspk = sortPFmaps(pfMap, pfMap_sm, normpfMap_sm, hist.SIspk);


%% ADDITIONAL PROCESSING IF Nepochs > 1
% Calculate place field maps for each epoch 
if Nepochs > 1
    % Initialise matrices
    bintime_e = zeros(Nepochs, Nbins);                         
    occMap_e = zeros(Nepochs, Nbins);                         
    spkMap_e = zeros(Ncells, Nbins, Nepochs);
    normspkMap_e = zeros(Ncells, Nbins, Nepochs);   
    bin_phi_e = zeros(Nepochs, Nbins);
    activephi_e = zeros(Ncells, Nbins, Nepochs);
    activespk_e = zeros(Ncells, Nbins, Nepochs);
    activet_e = zeros(Ncells, Nbins, Nepochs);
    spk_rate_e = zeros(Ncells, Nepochs);
    spk_amplrate_e = zeros(Ncells, Nepochs);
    bin_activity_e = zeros(Ncells, Nbins, Nepochs);
    
    hist_epochs.rMap = zeros(Ncells, Nbins, Nepochs);               
    hist_epochs.rMap_sm = zeros(Ncells, Nbins, Nepochs);            
    hist_epochs.normrMap_sm = zeros(Ncells, Nbins, Nepochs);     
    hist_epochs.infoMap = zeros(Ncells, 2, Nepochs); 
    hist_epochs.pfLoc = zeros(Ncells, Nepochs);
    hist_epochs.fieldSize = zeros(Ncells, Nepochs);
    hist_epochs.pfBins = zeros(Ncells, Nepochs);
    
    if doasd
        asd_epochs.rMap = zeros(Ncells, Nbins, Nepochs);               
        asd_epochs.rMap_sm = zeros(Ncells, Nbins, Nepochs);            
        asd_epochs.normrMap_sm = zeros(Ncells, Nbins, Nepochs);     
        asd_epochs.infoMap = zeros(Ncells, 2, Nepochs); 
        asd_epochs.pfLoc = zeros(Ncells, Nepochs);
        asd_epochs.fieldSize = zeros(Ncells, Nepochs);
        asd_epochs.pfBins = zeros(Ncells, Nepochs);
    end
    
    % Calculate PF maps
    e_bound = round( linspace(1,size(activespk,2),Nepochs+1) );
    
    % separate exploration into smaller intervals
    for e = 1:Nepochs
        bin_phi_e(e,:) = bin_phi(e_bound(e):e_bound(e+1));
        activephi_e(:,:,e) = activephi(:,e_bound(e):e_bound(e+1));
        activespk_e(:,:,e) = activespk(:,e_bound(e):e_bound(e+1));
        activet_e(:,:,e) = activet(:,e_bound(e):e_bound(e+1));
            
        [PFdata_e, hist_e, asd_e] = calcPFdata_1d(bin_phi_e(e,:), activephi_e(:,:,e), activespk_e(:,:,e), activet_e(:,:,e), Nbins, fr);
        phi_trials_e{e} = PFdata_e.phi_trials;
        spk_trials_e{e} = PFdata_e.spk_trials;
        bintime_trials{e} = PFdata_e.bintime_trials;
        bintime_e(e,:) = PFdata_e.bintime;
        spkRaster{e}{:} = PFdata_e.spkRaster;
        normspkRaster{e}{:} = PFdata_e.normspkRaster;
        activetrials{e} = PFdata_e.activetrials;
        spk_rate = PFdata_e.spk_rate;
        spk_amplrate = PFdata_e.spk_amplrate;
        bin_activity = PFdata_e.bin_activity;
        occMap = PFdata_e.occMap;
        spkMap = PFdata_e.spkMap;
        normspkMap = PFdata_e.normspkMap;
    end
end



% sort pf maps
hist_e.SIsec = sortPFmaps(hist_e.SIsec);
hist_e.SIspk = sortPFmaps(hist_e.SIspk);


%% Outputs
if Nepochs > 1
    PFdata_epochs.occMap = occMap_e;                         
    PFdata_epochs.spkMap = spkMap_e;
    PFdata_epochs.normspkMap = normspkMap_e;   
    PFdata_epochs.bin_phi = bin_phi_e;
    PFdata_epochs.activespk = activespk_e;
    PFdata_epochs.spk_rate = spk_rate_e;
    PFdata_epochs.spk_amplrate = spk_amplrate_e;
    PFdata_epochs.bin_activity = bin_activity_e;
else
    hist_epochs = [];
    if doasd, asd_epochs = []; end
end
if ~doasd, asd = []; end

varargout(1) = hist_epochs;
varargout(2) = asd_epochs;
end

function hSIstruct = sortPFmaps(rateMap, rateMap_sm, normrateMap_sm, hSIstruct)
    % Sort place field maps
    Nepochs = size(rateMap,3);
    if Nepochs == 1
        if ~isempty(hSIstruct.pcIdx)
            [ ~, sortIdx ] = sort( hSIstruct.pfLoc );
            hSIstruct.sortpcIdx = hSIstruct.pcIdx(sortIdx);
            hSIstruct.sort_pfMap = rateMap(sortIdx,:);
            if isfield(hSIstruct,'pfMap_sm')
                hSIstruct.sort_pfMap_sm = rateMap_sm(sortIdx,:);
                hSIstruct.sort_normpfMap_sm = normrateMap_sm(sortIdx,:);
            end
        end
    else
        for e = 1:Nepochs
            if ~isempty(hSIstruct.pcIdx{e})
                [ ~, sortIdx ] = sort( hSIstruct.pfLoc{e} );
                hSIstruct.sortpcIdx{e} = hSIstruct.pcIdx{e}(sortIdx);
                hSIstruct.sort_pfMap{e} = rateMap{e}(sortIdx,:);
                if isfield(hSIstruct,'pfMap_sm')
                    hSIstruct.sort_pfMap_sm{e} = rateMap_sm{e}(sortIdx,:);
                    hSIstruct.sort_normpfMap_sm{e} = normrateMap_sm{e}(sortIdx,:);
                end
            end
        end
    end
end

