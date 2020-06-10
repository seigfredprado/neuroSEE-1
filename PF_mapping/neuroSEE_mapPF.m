% Written by Ann Go
%
% This function generates place field maps if they don't yet exist and then
% sorts them according to location of maximum Skagg's information (or mutual 
% information if this is the chosen metric). It then
% saves the data into a mat file and generates summary plots.
%
%% INPUTS
%   spikes      : ncell rows 
%   downTrackdata   : cell of downsampled tracking data with fields x, y, phi, speed, time
%   data_locn   : repository of GCaMP data
%   file        : part of filename of video to be processed in the format
%                   yyyymmdd_hh_MM_ss
%   params      : settings
%
%% OUTPUTS
%   occMap      : occupancy map
%   spikeMap    : spike map (Ncells rows x Nbins columns)
%   infoMap     : information map 
%   activeTrackdata  : downsampled tracking data for when animal was moving; fields are
%                       x, y, phi, speed, time, spikes, spikes_pc

% place field maps
%   pfMap       : place field map obtained with histogram estimation (same size as spikeMap)
%   pfMap_sm    : smoothed version of pfMap 
%   pfMap_asd   : place field map obtained with ASD
%   normpfMap       : normalised place field map obtained with histogram estimation (same size as spikeMap)
%   normpfMap_sm    : normalised smoothed version of pfMap 
%   normpfMap_asd   : normalised place field map obtained with ASD

%   params

%% OUTPUTS for '1D' only 
% sorted according to location of maximum information
%   sorted_pfMap          
%   sorted_pfMap_sm  
%   sorted_pfMap_asd    

% normalised and sorted according to location of maximum information
%   sorted_normpfMap          
%   sorted_normpMap_sm  
%   sorted_normpfMap_asd    

% per trial spike maps
%   spikeMap_pertrial
%   normspikeMap_pertrial

%   pcIdx   : row indices of spikes corresponding to place cells
%   sortIdx : sorted row indices corresponding to sorted_pfMap

function [ hist, asd, PFdata, params ] = neuroSEE_mapPF( spikes, downTrackdata, data_locn, file, params, force, list, reffile)
    if nargin<8, reffile = []; end
    if nargin<7, list = []; end
    if nargin<6, force = 0; end

    mcorr_method = params.methods.mcorr_method;
    segment_method = params.methods.segment_method;
    if isfield(params.methods,'doasd')
        doasd = params.methods.doasd;
    else
        doasd = false;
    end
    
    if params.methods.dofissa
        str_fissa = 'FISSA';
    else
        str_fissa = 'noFISSA';
    end
    
    if isempty(list)
        fig_sdir = [data_locn,'Data/',file(1:8),'/Processed/',file,'/mcorr_',mcorr_method,'/',segment_method,'/',str_fissa,'/PFdata/'];
        fname_pref = file;
        fname_mat = [fig_sdir fname_pref '_PFmap_output.mat'];
    else
        [ mouseid, expname ] = find_mouseIDexpname(list);
        groupreg_method = params.methods.groupreg_method;
        imreg_method = params.methods.imreg_method;
        if strcmpi(imreg_method, mcorr_method)
            filedir = [ data_locn 'Analysis/' mouseid '/' mouseid '_' expname '/group_proc/' groupreg_method '_' imreg_method '_' segment_method '_'...
                        str_fissa '/' mouseid '_' expname '_imreg_ref' reffile '/'];
        else
            filedir = [ data_locn 'Analysis/' mouseid '/' mouseid '_' expname '/group_proc/' groupreg_method '_' imreg_method '_' segment_method '_'...
                        str_fissa '/' mouseid '_' expname '_imreg_ref' reffile '_' mcorr_method '/'];
        end
        fname_pref = [mouseid '_' expname '_ref' reffile];
        fname_mat = [filedir fname_pref '_PFmap_output.mat'];
        fig_sdir = [filedir '/PFdata/'];
    end
    
    if force || ~exist(fname_mat,'file')
        if isempty(list)
            str = sprintf( '%s: Generating place field maps\n', file );
        else
            str = sprintf( '%s: Generating place field maps\n', [mouseid '_' expname] );
        end
        cprintf(str)

        % If imaging timestamps exist, use them. If not, generate timestamps from
        % known scanning frame rate.
%         dir_timestamps = [data_locn 'Data/' file(1:8) '/Timestamps/'];
%         if exist(dir_timestamps,'dir')
%             imtime = extractImtime(dir_timestamps);
%         else
%            imtime = [];
%         end
        
        Nepochs = params.PFmap.Nepochs;
        if strcmpi(params.mode_dim,'1D')
            % Generate place field maps
            [hist, asd, PFdata] = generatePFmap_1d( spikes, downTrackdata, params, doasd );
           
            % Make plots
            if force || ~exist(fig_sdir,'dir')
                if ~exist(fig_sdir,'dir'), mkdir(fig_sdir); end
                plotPF_1d(hist, asd, PFdata, true, true, fig_sdir, fname_pref)
            end
        
            % Save output
            output.hist = hist;
            if doasd, output.asd = asd; end
            output.pfData = PFdata;
            output.params = params.PFmap;
            save(fname_mat,'-struct','output');
        else % '2D'
            [hist, asd, PFdata] = generatePFmap_2d(spikes, downTrackdata, params, doasd);
            
            % Make plots
            if force || ~exist(fig_sdir,'dir')
                if ~exist(fig_sdir,'dir'), mkdir(fig_sdir); end
                plotPF_2d( hist, asd, true, true, fig_sdir, fname_pref )
            end
        
            % Save output
            output.hist = hist;
            if doasd, output.asd = asd; end
            output.pfData = PFdata;
            output.params = params.PFmap;
            save(fname_mat,'-struct','output');
        end
        
        if isempty(list)
            currstr = sprintf( '%s: Place field maps generated\n', file );
        else
            currstr = sprintf( '%s: Place field maps generated\n', [mouseid '_' expname] );
        end
        refreshdisp(currstr,str)
    else
        m = load(fname_mat);
        hist = m.hist;
        if doasd, asd = m.asd; else, asd = []; end
        PFdata = m.pfData;
        params.PFmap = m.params;
        Nepochs = params.PFmap.Nepochs;
        
        % Make plots if necessary
        if ~exist(fig_sdir,'dir')
            mkdir(fig_sdir); 
            if strcmpi(params.mode_dim,'1D')
                plotPF_1d(hist, asd, PFdata, true, true, fig_sdir, fname_pref)
            else
                plotPF_2d( hist, asd, true, true, fig_sdir, fname_pref )
            end
        end
        
        if isempty(list)
            str = sprintf( '%s: Place field map data loaded\n', file );
        else
            str = sprintf( '%s: Place field map data loaded\n', [mouseid '_' expname] );
        end
        cprintf(str)
    end
end % function