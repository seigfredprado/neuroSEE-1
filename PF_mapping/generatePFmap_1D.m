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
%     spkMap_pertrial
%     normspkfMap_pertrial
%     pcIdx                 : row indices of original spikes corresponding
%                               to place cells
%   downData    : tracking data downsampled to imaging frequency, fields are
%                 x, y, r, phi, speed, t
%   activeData  : downsampled tracking data for when animal was moving, fields are
%                 x, y, r, phi, speed, t, spikes, spikes_pc 

function [ occMap, hist, asd, downData, activeData ] = generatePFmap_1d( spikes, imtime, trackData, params )
    
fr = params.fr;
Nbins = params.PFmap.Nbins;
Nepochs = params.PFmap.Nepochs;
Vthr = params.PFmap.Vthr;
histsmoothFac = params.PFmap.histsmoothFac;
Ncells = size(spikes,1);

%% Pre-process tracking data
tracktime = trackData.time;
x = trackData.x;
y = trackData.y;
r = trackData.r;
phi = trackData.phi;
speed = trackData.speed;

t0 = tracktime(1);                  % initial time in tracking data
nspikes = spikes; %bsxfun( @rdivide, bsxfun(@minus, spikes, min(spikes,[],2)), range(spikes,2) ); % normalisation
Nt = size(spikes,2);                % number of timestamps for spikes

% Convert -180:180 to 0:360
if min(phi)<0
   phi(phi<0) = phi(phi<0)+360;
end

% If no timestamps were recorded for Ca images, generate timestamps
% using known image frame rate
if isempty(imtime)
   dt = 1/fr;
   t = (t0:dt:Nt*dt)';
end

% Downsample tracking to Ca trace
downphi = interp1(tracktime,phi,t,'linear');
downx = interp1(tracktime,x,t,'linear');
downy = interp1(tracktime,y,t,'linear');
downspeed = interp1(tracktime,speed,t,'linear'); % mm/s
downr = interp1(tracktime,r,t,'linear'); % mm/s

% Consider only samples when the mouse is active
activex    = downx(downspeed > Vthr);
activey    = downy(downspeed > Vthr);
activephi  = downphi(downspeed > Vthr);
activespk = nspikes(:,downspeed > Vthr);
activet     = t(downspeed > Vthr);
activespeed = speed(downspeed > Vthr);
activer = r(downspeed > Vthr);

% Bin phi data
[bin_phi,~] = discretize(activephi,Nbins);


%% Identify place cells by first calculating PF maps for entire session
% (i.e. Nepochs = 1)

% Initialise matrices
spkMap = zeros(Ncells, Nbins);         % spike map
pfMap = zeros(Ncells, Nbins);            % place field map
pfMap_asd = zeros(Ncells, Nbins);        % place field map for asd
infoMap = zeros(Ncells, 2);              % mutual info
infoMap_asd = zeros(Ncells, 2);          % mutual info for asd

% Calculate PF maps
occMap = histcounts(bin_phi,Nbins);
for id = 1:Ncells
    z = activespk(id,:);

    % Spike rate maps
    for i = 1:Nbins
        spkMap(id,i) = sum(z(bin_phi == i));
    end

    % histogram estimation
    pfMap(id,:) = spkMap(id,:)./occMap;
    [infoMap(id,1), infoMap(id,2)] = infoMeasures(pfMap(id,:),occMap,0);

    % ASD estimation
    [pfMap_asd(id,:),~] = runASD_1d(bin_phi,z',Nbins);
    [infoMap_asd(id,:), infoMap_asd(id,:)] =...
        infoMeasures(pfMap_asd(id,:)',ones(Nbins,1),0);
end

% Identify place cells
[hist.pcIdx,asd.pcIdx] = filter_nonPC(bin_phi, activespk, infoMap, infoMap_asd, Nbins);
activespk_hist = activespk(hist.pcIdx,:);
activespk_asd = activespk(asd.pcIdx,:);
Npcs = length(hist.pcIdx);
Npcs_asd = length(asd.pcIdx);


%% Finalise place field maps, recalculate if Nepochs > 1
if Nepochs == 1
    hist.spkMap = spkMap(hist.pcIdx,:);
    hist.pfMap = pfMap(hist.pcIdx,:);
    for i = 1:Npcs
        hist.normspkMap(i,:) = hist.spkMap(i,:)./max(hist.spkMap(i,:));
        hist.pfMap_sm(i,:) = smoothdata(hist.pfMap(i,:),'gaussian',Nbins/histsmoothFac);
        hist.normpfMap(i,:) = hist.pfMap(i,:)./max(hist.pfMap(i,:));
        hist.normpfMap_sm(i,:) = hist.pfMap_sm(i,:)./max(hist.pfMap_sm(i,:));
    end
    hist.infoMap = infoMap(hist.pcIdx,:);
    
    asd.spkMap = spkMap(asd.pcIdx,:);
    asd.pfMap = pfMap_asd(asd.pcIdx,:);
    for i = 1:Npcs_asd
        asd.normspkMap(i,:) = asd.spkMap(i,:)./max(asd.spkMap(i,:));
        asd.normpfMap(i,:) = asd.pfMap(i,:)./max(asd.pfMap(i,:));
    end
    asd.infoMap = infoMap_asd(asd.pcIdx,:);

else
    % Calculate PF maps for each epoch
    % Initialise matrices
    occMap = zeros(Nepochs, Nbins);                         
    hist.spkMap = zeros(Npcs, Nbins, Nepochs);            
    hist.normspkMap = zeros(Npcs, Nbins, Nepochs);            
    hist.pfMap = zeros(Npcs, Nbins, Nepochs);               
    hist.pfMap_sm = zeros(Npcs, Nbins, Nepochs);            
    hist.normpfMap = zeros(Npcs, Nbins, Nepochs);        
    hist.normpfMap_sm = zeros(Npcs, Nbins, Nepochs);     
    hist.infoMap = zeros(Npcs, 2, Nepochs);              
    asd.spkMap = zeros(Npcs_asd, Nbins, Nepochs);            
    asd.normspkMap = zeros(Npcs_asd, Nbins, Nepochs);            
    asd.pfMap = zeros(Npcs_asd, Nbins, Nepochs);              
    asd.normpfMap = zeros(Npcs_asd, Nbins, Nepochs);          
    asd.infoMap = zeros(Npcs_asd, 2, Nepochs);               

    % Calculate PF maps
    e_bound = round( linspace(1,size(activespk,2),Nepochs+1) );
    for id = 1:Npcs
        z = activespk_hist(id,:);

        % separate exploration in smaller intervals
        for e = 1:Nepochs
            bin_phi_e = bin_phi(e_bound(e):e_bound(e+1));
            spike_e = z(e_bound(e):e_bound(e+1));

            % Occupancy and spike rate maps
            occMap(e,:) = histcounts(bin_phi_e,Nbins);
            for i = 1:Nbins
                hist.spkMap(id,i,e) = sum(spike_e(bin_phi_e == i));
            end
            hist.normspkMap(id,:,e) = hist.spkMap(id,:,e)./max(hist.spkMap(id,:,e));
            
            % histogram estimation
            hist.pfMap(id,i,e) = hist.spkMap(id,:,e)./occMap(e,:);
            hist.pfMap(isnan(hist.pfMap)) = 0;
            hist.pfMap_sm(id,i,e) = smoothdata(hist.pfMap(id,i,e),'gaussian',Nbins/histsmoothFac);

            hist.normpfMap(id,i,e) = hist.pfMap(id,i,e)./max(hist.pfMap(id,i,e));
            hist.normpfMap_sm(id,i,e) = hist.pfMap_sm(id,i,e)./max(hist.pfMap_sm(id,i,e));
            [hist.infoMap(id,1,e), hist.infoMap(id,2,e)] = infoMeasures(hist.pfMap(id,i,e),occMap(e,:),0);
        end
    end
    for id = 1:Npcs_asd
        z = activespk_asd(id,:);

        % separate exploration in smaller intervals
        for e = 1:Nepochs
            bin_phi_e = bin_phi(e_bound(e):e_bound(e+1));
            spike_e = z(e_bound(e):e_bound(e+1));

            % Occupancy and spike rate maps
            occMap(e,:) = histcounts(bin_phi_e,Nbins);
            for i = 1:Nbins
                asd.spkMap(id,i,e) = sum(spike_e(bin_phi_e == i));
            end
            asd.normspkMap(id,:,e) = asd.spkMap(id,:,e)./max(asd.spkMap(id,:,e));

            % histogram estimation
            asd.pfMap(id,i,e) = asd.spkMap(id,:,e)./occMap(e,:);
            asd.pfMap(isnan(asd.pfMap)) = 0;

            asd.normpfMap(id,i,e) = asd.pfMap(id,i,e)./max(asd.pfMap(id,i,e));
            [asd.infoMap(id,1,e), asd.infoMap(id,2,e)] = infoMeasures(asd.pfMap(id,i,e),occMap(e,:),0);
        end
    end
end

% Calculate PF maps per trial
dthr = 190;
phi_bound = find( abs(diff(activephi)) > dthr );
Ntrials = length(phi_bound)-1;

hist.spkMap_pertrial = zeros(length(phi_bound)-1,Nbins,Npcs);
hist.normspkMap_pertrial = zeros(length(phi_bound)-1,Nbins,Npcs);

for i = 1:Npcs
    z = activespk_hist(i,:);
    for j = 1:Ntrials
        phi = bin_phi(phi_bound(j):phi_bound(j+1)-1);
        spike = z(phi_bound(j):phi_bound(j+1)-1);

        for k = 1:Nbins
            hist.spkMap_pertrial(j,k,i) = sum(spike(phi == k));
        end

        hist.normspkMap_pertrial(j,:,i) = hist.spkMap_pertrial(j,:,i)./max(hist.spkMap_pertrial(j,:,i));
        hist.normspkMap_pertrial(isnan(hist.normspkMap_pertrial)) = 0;
    end
end

asd.spkMap_pertrial = zeros(length(phi_bound)-1,Nbins,Npcs_asd);
normasd.spkMap_pertrial = zeros(length(phi_bound)-1,Nbins,Npcs_asd);

for i = 1:Npcs_asd
    z = activespk_asd(i,:);
    for j = 1:Ntrials
        phi = bin_phi(phi_bound(j):phi_bound(j+1)-1);
        spike = z(phi_bound(j):phi_bound(j+1)-1);

        for k = 1:Nbins
            asd.spkMap_pertrial(j,k,i) = sum(spike(phi == k));
        end

        normasd.spkMap_pertrial(j,:,i) = asd.spkMap_pertrial(j,:,i)./max(asd.spkMap_pertrial(j,:,i));
        normasd.spkMap_pertrial(isnan(normasd.spkMap_pertrial)) = 0;
    end
end

% Outputs
downData.x = downx;
downData.y = downy;
downData.r = downr;
downData.phi = downphi;
downData.speed = downspeed;
downData.t = t;

activeData.x = activex;
activeData.y = activey;
activeData.r = activer;
activeData.phi = activephi;
activeData.speed = activespeed;
activeData.t = activet;
activeData.spikes_hist = activespk_hist;
activeData.spikes_asd = activespk_asd; 

end


