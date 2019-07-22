% Written by Ann Go, adapted from Giuseppe's PF_ASD_2d.m

function [occMap, spkMap, spkIdx, hist, asd, downData, activeData] = generatePFmap_2d(spikes, imtime, trackData, params)

fr = params.fr;
Nbins = params.PFmap.Nbins;
Nepochs = params.PFmap.Nepochs;     % number of epochs to divide trial in
Vthr = params.PFmap.Vthr;
Ncells = size(spikes,1);
histsmoothFac = params.PFmap.histsmoothFac;

%% Pre-process tracking data
tracktime = trackData.time;
xcont = trackData.x;
ycont = trackData.y;
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
downx   = interp1(tracktime,xcont,t,'linear');
downy   = interp1(tracktime,ycont,t,'linear');
downspeed = interp1(tracktime,speed,t,'linear'); % mm/s
downr   = interp1(tracktime,r,t,'linear'); % mm/s

% Consider only samples when the mouse is active
activex    = downx(downspeed > Vthr);
activey    = downy(downspeed > Vthr);
activephi  = downphi(downspeed > Vthr);
activespk  = nspikes(:,downspeed > Vthr);
activet     = t(downspeed > Vthr);
activespeed = speed(downspeed > Vthr);
activer    = r(downspeed > Vthr);

xcont = activex;
ycont = activey;
xcont = (xcont-min(xcont))/(max(xcont)-min(xcont)); % normalised 0 mean
ycont = (ycont-min(ycont))/(max(ycont)-min(ycont));
xycont  = [xcont,ycont];

% discretize x and y position 
x1 = linspace(0,1.0001,Nbins(1)+1);
y1 = linspace(0,1.0001,Nbins(2)+1);
x = floor((xycont(:,1)-x1(1))/(x1(2)-x1(1)))+1;
y = floor((xycont(:,2)-y1(1))/(y1(2)-y1(1)))+1;

occMap = full(sparse(x, y, 1, Nbins(1), Nbins(2)));
mode = 0; % the mask is obtained by imfill only
envMask_hist = getEnvEdgePrior(occMap,mode); % hist

mode = 2; % the mask is obtained by dilation and imfill
envMask_asd = getEnvEdgePrior(occMap,mode); % ASD
xyind = sub2ind([Nbins(1),Nbins(2)],x,y); % flatten bin tracking (for ASD)

% find which neurons are spiking
a = zeros(size(spikes));
for ii = 1:Ncells
    a(ii) = sum(activespk(ii,:));
end
spkIdx = find(a); % store indices
Nspk = length(spkIdx);

% initialise  variables to store results
occMap = zeros(Nbins(1), Nbins(2), Nepochs);
spkMap = zeros(Nbins(1), Nbins(2), Nspk, Nepochs);
hist.pfMap    = zeros(Nbins(1), Nbins(2), Nspk, Nepochs);
hist.pfMap_sm = zeros(Nbins(1), Nbins(2), Nspk, Nepochs);
hist.infoMap  = zeros(Nspk, 2, Nepochs);
asd.pfMap     = zeros(Nbins(1), Nbins(2), Nspk, Nepochs);
asd.infoMap   = zeros(Nspk, 2, Nepochs);

e_bound = round(linspace(1,size(activespk,2),Nepochs+1));
for id = 1:Nspk
    z = activespk(spkIdx(id),:);
    
    % separate exploration in smaller intervals
    for e = 1:Nepochs
        spike_e = z(e_bound(e):e_bound(e+1));
        
        % histogram estimation
        occMap(:,:,e) = full(sparse(x(e_bound(e):e_bound(e+1)), y(e_bound(e):e_bound(e+1)), 1,Nbins(1), Nbins(2)));
        spkMap(:,:,id,e) = full(sparse(x(e_bound(e):e_bound(e+1)), y(e_bound(e):e_bound(e+1)), spike_e, Nbins(1), Nbins(2)));
        hist.pfMap(:,:,id,e) = spkMap(:,:,id,e)./occMap(:,:,e);
        hist.pfMap(isnan(hist.pfMap)) = 0;
        hhh = imgaussfilt(hist.pfMap(:,:,id,e), Nbins(1)/histsmoothFac); hhh(~envMask_hist) = 0;
        hist.pfMap_sm(:,:,id,e) = hhh;
    
        % ASD estimation
        xyind_e = xyind(e_bound(e):e_bound(e+1));
        [kasd,~] = runASD_2d(xyind_e',spike_e',Nbins,envMask_asd);
        if min(kasd)<0; kasd = kasd-min(kasd); end
        asd.pfMap(:,:,id,e) = kasd;
        
        % info estimation
        [hist.infoMap(id,1,e), hist.infoMap(id,2,e)] = infoMeasures(hist.pfMap(:,:,id,e),occMap(:,:,e),0);
        [asd.infoMap(id,1,e), asd.infoMap(id,2,e)] = ...
            infoMeasures(asd.pfMap(:,:,id,e), ones(Nbins(1),Nbins(2)), 0);
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
activeData.spikes = activespk;


end