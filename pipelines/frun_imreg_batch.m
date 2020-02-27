% Written by Ann Go
%
% This script implements image registration of the non-reference files in
% 'list' to the reference file 'reffile'. This script is designed to be run
% on the hpc server where array_id loops through values specified in the
% hpc script.
%
% INPUTS
% array_id  : number which serves as array index for files in 'list'
% list      : name of text file containing filenames of files to be compared.
%           Typically in the format 'list_m##_expname.txt'.
%   e.g.    'list_m62_fam1nov-fam1.txt'         - all fam1 files in fam1nov experiment
%           'list_m62_fam1nov.txt'              - all files in fam1nov experiments
%           'list_m79_fam1_s1-5.txt'            - all fam1 files across 5 sessions           
%           'list_m86_open_s1-2.txt'            - all open field files across 2 sessions
% reffile   : file to be used as registration template. This file is
%               usually part of 'list' but does not have to be. This file
%               must have already been motion corrected.
% refChannel : channel (red or green) to be used as registation template
% slacknotify : flag to send Slack notification when processing is started
%               or has ended
% force  : flag to force generation of comparison figures even though they
%           already exist


function frun_imreg_batch( array_id, list, reffile, refChannel, slacknotify, force )

if nargin<6, force = false; end
if nargin<5, slacknotify = false; end
if nargin<4, refChannel = 'green'; end
% if nargin<3, see line 29
tic

%% Load module folders and define data directory

test = false;                      % flag to use one of smaller files in test folder)
mcorr_method = 'normcorre-nr';     % [fftRigid, normcorre, normcorre-nr, normcorre-r]

[data_locn,comp,err] = load_neuroSEEmodules(test);
if ~isempty(err)
    beep
    cprintf('Errors',err);    
    return
end
if strcmpi(comp,'hpc')
    maxNumCompThreads(32);      % max # of computational threads, must be the same as # of ncpus specified in jobscript (.pbs file)
end

%% Files

listfile = [data_locn 'Digital_Logbook/lists/' list];
files = extractFilenamesFromTxtfile( listfile );
if nargin<3, reffile = files(1,:); end

% Send Ann slack message
if slacknotify
    if array_id == 1
        slacktext = [list(6:end-4) ': registering 1 of ' num2str(size(files,1)) 'files'];
        neuroSEE_slackNotify( slacktext );
    end
end

% image to be registered
file = files(array_id,:);
params.methods.mcorr_method = mcorr_method;
params.mcorr.refChannel = refChannel;

if ~strcmpi( file, reffile )

    filedir = [data_locn 'Data/' file(1:8) '/Processed/' file '/mcorr_' mcorr_method '_ref' reffile '/'];
    if force || ~exist([filedir file '_imreg_ref' reffile '_output.mat'],'file')
        imG = read_file([ data_locn 'Data/' file(1:8) '/2P/' file '_2P/' file '_2P_XYT_green.tif']);
        imR = read_file([ data_locn 'Data/' file(1:8) '/2P/' file '_2P/' file '_2P_XYT_red.tif']);
    else
        imG = zeros(512,512);
        imR = zeros(512,512);
    end


    %% Image registration 
    params.mcorr.normcorre_nr = NoRMCorreSetParms(...
                'd1',size(imG,1),...
                'd2',size(imG,2),...
                'grid_size',[64,64],...
                'overlap_pre',[64,64],...
                'overlap_post',[64,64],...
                'iter',1,...
                'use_parallel',false,...
                'max_shift',20,...
                'mot_uf',4,...
                'bin_width',200,...
                'max_dev',3,...
                'us_fac',50,...
                'init_batch',200);

    try
        [ ~, ~, ~, ~ ] = neuroSEE_imreg( imG, imR, data_locn, file, reffile, params, force );
    catch
        fprintf('%s: Error in image registration, changing max_shift to 15\n', file);
        params.nonrigid.max_shift = 15;
        [ ~, ~, ~, ~ ] = neuroSEE_imreg( imG, imR, data_locn, file, reffile, params, force );
    end

    % Send Ann slack message
    if slacknotify
        if array_id == size(files,1)
            slacktext = [list(6:end-4) ': registering ' num2str(size(files,1)) ' of ' num2str(size(files,1)) 'files'];
            neuroSEE_slackNotify( slacktext );
        end
    end
    
    t = toc;
    str = sprintf('%s: Processing done in %g hrs\n', file, round(t/3600,2));
    cprintf(str)

end

end
