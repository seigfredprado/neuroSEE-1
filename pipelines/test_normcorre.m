file = '20190406_20_33_01';

[data_locn,~,~] = load_neuroSEEmodules(true);
mcorr_method = 'normcorre';

d = 512;
% NoRMCorre-rigid
params.rigid = NoRMCorreSetParms(...
                'd1',d,...        % width of image [default: 512]  *Regardless of user-inputted value, neuroSEE_motioncorrect reads this 
                'd2',d,...        % length of image [default: 512] *value from actual image    
                'max_shift',20,...          % default: 50
                'bin_width',200,...         % default: 200
                'us_fac',50,...             % default: 50
                'init_batch',200);          % default: 200
            
% NoRMCorre-nonrigid
params.nonrigid = NoRMCorreSetParms(...
                'd1',d,...        % width of image [default: 512]  *Regardless of user-inputted value, neuroSEE_motioncorrect reads this 
                'd2',d,...        % length of image [default: 512] *value from actual image    
                'grid_size',[32,32],...     % default: [32,32]
                'overlap_pre',[32,32],...   % default: [32,32]
                'overlap_post',[32,32],...  % default: [32,32]
                'iter',1,...                % default: 1
                'use_parallel',false,...    % default: false
                'max_shift',15,...          % default: 50
                'mot_uf',4,...              % default: 4
                'bin_width',200,...         % default: 200
                'max_dev',3,...             % default: 3
                'us_fac',50,...             % default: 50
                'init_batch',200);          % default: 200
            
% Load image
[imG,imR] = load_imagefile( data_locn, file );

% Motion correction
[ imG, imR, ~, ~, ~, ~, ~, ~ ] = normcorre_2ch( imG, imR, params.rigid );

[ imG, imR, out_g, out_r, col_shift, shifts, template, ~ ] = normcorre_2ch( imG, imR, params.nonrigid );


    filedir = fullfile( data_locn, 'Data/', file(1:8), '/Processed/', file, '/mcorr_normcorre/' );
    if ~exist( filedir, 'dir' ), mkdir( filedir ); end
    
    fname_tif_gr_mcorr = [filedir file '_2P_XYT_green_mcorr.tif'];
    fname_tif_red_mcorr = [filedir file '_2P_XYT_red_mcorr.tif'];
    fname_mat_mcorr = [filedir file '_mcorr_output.mat'];

    % Save motion corrected tif images
    prevstr = sprintf( '%s: Saving motion corrected tif images...\n', file );
    cprintf('Text',prevstr);
        writeTifStack( imG,fname_tif_gr_mcorr );
        writeTifStack( imR,fname_tif_red_mcorr );
    str = sprintf( '%s: Motion corrected tif images saved\n', file );
    refreshdisp( str, prevstr );