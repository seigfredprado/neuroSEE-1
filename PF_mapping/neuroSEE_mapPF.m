% Written by Ann Go
%
% This function generates place field maps if they don't yet exist and then
% sorts them according to location of maximum Skagg's information. It then
% saves the data into a mat file and generates summary plots.
%
%% INPUTS
%   spikes      : ncell rows 
%   trackData   : cell of tracking data with fields x, y, phi, speed, time
%   data_locn   : repository of GCaMP data
%   file        : part of filename of video to be processed in the format
%                   yyyymmdd_hh_MM_ss
%   params      : settings
%
%% OUTPUTS
%   occMap      : occupancy map
%   spikeMap    : spike map (Ncells rows x Nbins columns)
%   infoMap     : information map 
%   downData    : tracking data downsampled to imaging frequency, fields are
%                   x, y, phi, speed, time
%   activeData  : downsampled tracking data for when animal was moving, fields are
%                   x, y, phi, speed, time, spikes, spikes_pc

% place field maps
%   pfMap       : place field map obtained with histogram estimation (same size as spikeMap)
%   pfMap_sm    : smoothed version of pfMap 
%   pfMap_asd   : place field map obtained with ASD
%   normpfMap       : normalised place field map obtained with histogram estimation (same size as spikeMap)
%   normpfMap_sm    : normalised smoothed version of pfMap 
%   normpfMap_asd   : normalised place field map obtained with ASD

%   params

%% OUTPUTS for '1D' only 
% sorted according to location of maximum mutual information
%   sorted_pfMap          
%   sorted_pfMap_sm  
%   sorted_pfMap_asd    

% normalised and sorted according to location of maximum mutual information
%   sorted_normpfMap          
%   sorted_normpMap_sm  
%   sorted_normpfMap_asd    

% per trial spike maps
%   spikeMap_pertrial
%   normspikeMap_pertrial

%   pcIdx   : row indices of spikes corresponding to place cells
%   sortIdx : sorted row indices corresponding to sorted_pfMap

function varargout = neuroSEE_mapPF( spikes, trackData, data_locn, file, params, force)
    
    if nargin<6, force = 0; end

    mcorr_method = params.methods.mcorr_method;
    segment_method = params.methods.segment_method;
    
    if params.methods.dofissa
        str_fissa = 'FISSA';
    else
        str_fissa = 'noFISSA';
    end
    filedir = [data_locn,'Data/',file(1:8),'/Processed/',file,'/mcorr_',mcorr_method,'/',segment_method,'/',str_fissa,'/PFmaps/'];
    fname_mat = [filedir file '_PFmap_output.mat'];
    
    if force || ~exist(fname_mat,'file')
        str = sprintf( '%s: Generating place field maps\n', file );
        cprintf(str)

        % If imaging timestamps exist, use them. If not, generate timestamps from
        % known scanning frame rate.
%         dir_timestamps = [data_locn 'Data/' file(1:8) '/Timestamps/'];
%         if exist(dir_timestamps,'dir')
%             imtime = extractImtime(dir_timestamps);
%         else
            imtime = [];
%         end

        if strcmpi(params.mode_dim,'1D')
            % Generate place field maps
            [occMap, spikeMap, normspikeMap, infoMap, infoMap_asd,...
             pfMap, pfMap_sm, pfMap_asd, ...
             normpfMap, normpfMap_sm, normpfMap_asd, ...
             downData, activeData, pcIdx, ...
             spikeMap_pertrial, normspikeMap_pertrial] ...
               = generatePFmap_1d( spikes, imtime, trackData, params );
           
            % If 1D, sort place field maps 
            [ sorted_pfMap, sortIdx ] = sortPFmap_1d( pfMap, infoMap, Nepochs );
            sorted_pfMap_sm = pfMap_sm(sortIdx,:,:);
            sorted_pfMap_asd = pfMap_asd(sortIdx,:,:);
            sorted_normpfMap = normpfMap(sortIdx,:,:);
            sorted_normpfMap_sm = normpfMap_sm(sortIdx,:,:);
            sorted_normpfMap_asd = normpfMap_asd(sortIdx,:,:);
            
            % Make plots
            makeplot_1d(occMap, spikeMap, normspikeMap, infoMap, infoMap_asd, ...
                        pfMap, pfMap_sm, pfMap_asd, ...
                        normpfMap, normpfMap_sm, normpfMap_asd, ...
                        spikeMap_pertrial, normspikeMap_pertrial);
        
            % Save output
            output.occMap = occMap;
            output.spikeMap = spikeMap;
            output.normspikeMap = normspikeMap;
            output.infoMap = infoMap;
            output.infoMap_asd = infoMap_asd;
            output.pfMap = pfMap;
            output.pfMap_sm = pfMap_sm;
            output.pfMap_asd = pfMap_asd;
            output.normpfMap = normpfMap;
            output.normpfMap_sm = normpfMap_sm;
            output.normpfMap_asd = normpfMap_asd;
            output.downData = downData;
            output.activeData = activeData;
            output.pcIdx = pcIdx;output.sorted_pfMap = sorted_pfMap;
            output.spikeMap_pertrial = spikeMap_pertrial;
            output.normspikeMap_pertrial = normspikeMap_pertrial;
            output.sorted_pfMap_sm = sorted_pfMap_sm;
            output.sorted_pfMap_asd = sorted_pfMap_asd;
            output.sorted_normpfMap = sorted_normpfMap;
            output.sorted_normpfMap_sm = sorted_normpfMap_sm;
            output.sorted_normpfMap_asd = sorted_normpfMap_asd;
            output.sortIdx = sortIdx;
            output.params = params.PFmap;
            save(fname_mat,'-struct','output');
        else % '2D'
        end
              
        currstr = sprintf( '%s: Place field maps generated\n', file );
        refreshdisp(currstr,str)
    else
        if strcmpi(params.mode_dim,'1D')
            m = load(fname_mat);
            occMap = m.occMap;
            spikeMap = m.spikeMap;
            normspikeMap = m.normspikeMap;
            infoMap = m.infoMap;
            infoMap_asd = m.infoMap_asd;
            pfMap = m.pfMap;
            pfMap_sm = m.pfMap_sm;
            pfMap_asd = m.pfMap_asd;
            normpfMap = m.normpfMap;
            normpfMap_sm = m.normpfMap_sm;
            normpfMap_asd = m.normpfMap_asd;
            downData = m.downData;
            activeData = m.activeData;
            params.PFmap = m.params;
            sorted_pfMap = m.sorted_pfMap;
            sorted_pfMap_sm = m.sorted_pfMap_sm;
            sorted_pfMap_asd = m.sorted_pfMap_asd;
            sorted_normpfMap = m.sorted_normpfMap;
            sorted_normpfMap_sm = m.sorted_normpfMap_sm;
            sorted_normpfMap_asd = m.sorted_normpfMap_asd;
            spikeMap_pertrial = m.spikeMap_pertrial;
            normspikeMap_pertrial = m.normspikeMap_pertrial;
            pcIdx = m.pcIdx;
            sortIdx = m.sortIdx;
        else % '2D'
        end
            
        str = sprintf( '%s: Place field map data loaded\n', file );
        cprintf(str)
    end
    
    varargout{1} = occMap;
    varargout{2} = spikeMap;
    varargout{3} = normspikeMap;
    varargout{4} = infoMap;
    varargout{5} = infoMap_asd;
    varargout{6} = pfMap;
    varargout{7} = pfMap_sm;
    varargout{8} = pfMap_asd;
    varargout{9} = normpfMap;
    varargout{10} = normpfMap_sm;
    varargout{11} = normpfMap_asd;
    varargout{12} = downData;
    varargout{13} = activeData;
    varargout{14} = params;
    varargout{15} = sorted_pfMap;
    varargout{16} = sorted_pfMap_sm;
    varargout{17} = sorted_pfMap_asd;
    varargout{18} = sorted_normpfMap;
    varargout{19} = sorted_normpfMap_sm;
    varargout{20} = sorted_normpfMap_asd;
    varargout{21} = spikeMap_pertrial;
    varargout{22} = normspikeMap_pertrial;
    varargout{23} = pcIdx;
    varargout{24} = sortIdx;
    
    function makeplot_1d(occMap, spikeMap, normspikeMap, infoMap, infoMap_asd, ...
                        sorted_pfMap, sorted_pfMap_sm, sorted_pfMap_asd, ...
                        sorted_normpfMap, sorted_normpfMap_sm, sorted_normpfMap_asd, ...
                        spikeMap_pertrial, normspikeMap_pertrial)
        % summary of occMap, spikeMap, pfMaps
        for e = 1:Nepochs
            fh = figure('Position',[1087 648 500 800]);
            subplot(13,13,2:5); imagesc(occMap);
                xticks([]); yticks([]);
                title('Occupancy map'); colorbar;
            subplot(13,13,[10:13,18:21,26:29]);
                imagesc(spikeMap(sortIdx,:)); 
                xticks([]); yticks([]); ylabel('Cell #');
                title('Spike map'); colorbar;
            subplot(13,13,[33,41,49]); imagesc(infoMap(sortIdx,1));
                xticks([]); 
                yticks([1 Npcs]); xticklabels([1 Npcs]); ylabel('Cell #'); 
                title('Max MI'); colorbar;
            subplot(13,13,[34:37,42:45,50:53]);    
                imagesc(sorted_pfMap); 
                xticks([]); yticks([]);
                title('Hist: Place field map'); colorbar;
            subplot(13,13,[58:61,66:69,74:77]);    
                imagesc(sorted_pfMap_sm); 
                xticks([]); yticks([]); ylabel('Cell #');
                title('Hist: Smoothened place field map'); colorbar; 
            subplot(13,13,[81,89,97]); imagesc(infoMap_asd(sortIdx,1));
                xticks([]); 
                yticks([1 Npcs]); xticklabels([1 Npcs]); ylabel('Cell #'); 
                title('Max MI'); colorbar;
            subplot(13,13,[82:85,90:93,98:101]);    
                imagesc(sorted_pfMap_asd); 
                xticks([1 15 30]); xticklabels([1 50 100]); xlabel('Position (cm)');
                yticks([]); 
                % degperbin = 360/Nbins; xticklabels(degperbin*(Nbins/6:Nbins/6:Nbins));
                colorbar; % caxis([0,0.005]);
                title('ASD: Place field map'); 
            subplot(13,13,[14:16,22:24,30:32]);
                imagesc(normspikeMap(sortIdx,:)); xticks([]); yticks([]);
                title('Normalised spike map');
            subplot(13,13,[38:40,46:48,54:56]);    
                imagesc(sorted_normpfMap); 
                xticks([]); yticks([]); ylabel('Cell #');
                title('Hist: Normalised pf map'); 
            subplot(13,13,[62:64,70:72,78:80]);    
                imagesc(sorted_normpfMap_sm); 
                xticks([]); yticks([]); ylabel('Cell #');
                title('Hist: Normalised smoothened pf map'); 
            subplot(13,13,[86:88,94:96,102:104]);    
                imagesc(sorted_normpfMap_asd); 
                xticks([1 15 30]); xticklabels([1 50 100]); xlabel('Position (cm)');
                yticks([]); ylabel('Cell #');
                % degperbin = 360/Nbins; xticklabels(degperbin*(Nbins/6:Nbins/6:Nbins));
                title('ASD: Normalised pf map'); 
                
            if Nepochs == 1
                fname_fig = [filedir file '_PFmaps'];
            else
                fname_fig = [filedir file '_PFmaps_' num2str(e) 'of' num2str(Nepochs)];
            end
            savefig( fh, fname_fig );
            saveas( fh, fname_fig, 'pdf' );
            close( fh );
        end
        
        % per trial spike maps
        Ntrials = size(spikeMap_pertrial,1);
        nRow = 5; nCol = 8;
        nPlot = nRow*nCol;
        for ii=0:Npcs/nPlot
            fh = figure;
            ha = tight_subplot(nRow,nCol,[.01 .01],[.01 .05],[.01 .01]);
            for jj=0:nPlot-1
                if (ii*nPlot+jj+1) <= Ncells
                    axes(ha(+jj+1));
                    imagesc(spikeMap_pertrial(:,:,ii*nPlot+jj+1)); 
                    yticks(1:Ntrials:Ntrials); yticklabels([1,Ntrials]); ylabel('Trial #');
                    xticks([1 15 30]); xticklabels([1 50 100]); xlabel('Position (cm)');
                    axis off; title(['Cell ' num2str(ii*nPlot+jj+1)]);
                end
            end
            fname_fig = [filedir file '_spike_pertrial_' num2str(ii)];
            savefig( fh, fname_fig );
            saveas( fh, fname_fig, 'pdf' );
            close( fh );
        end 

        for ii=0:Npcs/nPlot
            fh = figure;
            ha = tight_subplot(nRow,nCol,[.01 .01],[.01 .05],[.01 .01]);
            for jj=0:nPlot-1
                if (ii*nPlot+jj+1) <= Ncells
                    axes(ha(+jj+1));
                    imagesc(normspikeMap_pertrial(:,:,ii*nPlot+jj+1)); 
                    yticks(1:Ntrials:Ntrials); yticklabels([1,Ntrials]); ylabel('Trial #');
                    xticks([1 15 30]); xticklabels([1 50 100]); xlabel('Position (cm)');
                    axis off; title(['Cell ' num2str(ii*nPlot+jj+1)]);
                end
            end
            fname_fig = [filedir file '_normspike_pertrial_' num2str(ii)];
            savefig( fh, fname_fig );
            saveas( fh, fname_fig, 'pdf' );
            close( fh );
        end 
        
        % remapping within a session
        if Nepochs > 1
            fh = figure;
            for ei = 1:Nepochs % rows: sorting
                for ej = 1:Nepochs % cols: epochs 
                    subplot(Nepochs, Nepochs, (ei-1)*Nepochs + ej); imagesc(sorted_normpfMap(sortIdx(:,ei),:,ej)); 
                    title(['Epoch ' num2str(ej)]); ylabel(['Epoch' num2str(ei) ' sorting']);
                end
            end
            fname_fig = [filedir file '_remapping_hist'];
            savefig( fh, fname_fig );
            saveas( fh, fname_fig, 'pdf' );
            close( fh );
            
            fh = figure;
            for ei = 1:Nepochs % rows: sorting
                for ej = 1:Nepochs % cols: epochs 
                    subplot(Nepochs, Nepochs, (ei-1)*Nepochs + ej); imagesc(sorted_normpfMap_asd(sortIdx(:,ei),:,ej)); 
                    title(['Epoch ' num2str(ej)]); ylabel(['Epoch' num2str(ei) ' sorting']);
                end
            end
            fname_fig = [filedir file '_remapping_asd'];
            savefig( fh, fname_fig );
            saveas( fh, fname_fig, 'pdf' );
            close( fh );
        end
    end

end % function


