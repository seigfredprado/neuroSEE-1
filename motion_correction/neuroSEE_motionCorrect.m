% Written by Ann Go
%
% This function implements motion correction on red and green channel
% images
%
% INPUTS
%   imG         : matrix of green image stack
%   imR         : matrix of red image stack
%   data_locn   : GCaMP data repository
%   file        : part of file name of image stacks in the format
%                   yyyymmdd_HH_MM_SS
%   mcorr_method: motion correction method
%                   1- CaImAn NoRMCorre method
%                   2- fft-rigid method (Katie's)
%   params      : parameters for specific motion correction method
%   force       : if =1, motion correction will be done even though motion
%                   corrected images already exist
% OUTPUTS
%   imG         : matrix of motion corrected green image stack
%   imR         : matrix of motion corrected red image stack
%   mcorr_output: cell array containing
%                   green.[ meanframe, meanregframe ]
%                   red.[ meanframe, meanregframe ]
%                   shifts.[ zipper_shift, shifts ]
%                   template
%   params      : parameters for specific motion correction method

function [ imG, imR, mcorr_output, params ] = neuroSEE_motionCorrect(...
                                                imG, imR, data_locn, file, mcorr_method, params, force )
    
    if nargin<7, force = 0;      end
    
    if mcorr_method == 1
        filedir = fullfile( data_locn, 'Data/', file(1:8), '/Processed/', file, '/NoRMCorre/' );
    else
        filedir = fullfile( data_locn, 'Data/', file(1:8), '/Processed/', file, '/fft_rigid/' );
    end
    
    if ~exist( filedir, 'dir' ), mkdir( filedir ); end
    fname_tif_gr_mcorr = [filedir file '_2P_XYT_green_mcorr.tif'];
    fname_tif_red_mcorr = [filedir file '_2P_XYT_red_mcorr.tif'];
    fname_mat_mcorr = [filedir file '_mcorr_output.mat'];
    fname_fig = [filedir file '_mcorr_summary.fig'];
        
    % If asked to force overwrite, run motion correction right away
    if force
        if mcorr_method == 1
            [ imG, imR, out_g, out_r, shifts, template, ~ ] = normcorre_2ch( imG, imR, params.nonrigid );
            mcorr_output.params = params.nonrigid;
        else
            mcorr_output.imscale = params.imscale;
            mcorr_output.Nimg_ave = params.Nimg_ave;
            mcorr_output.refChannel = params.refChannel;
            mcorr_output.redoT = params.redoT;
            [ imG, imR, out_g, out_r, shifts, template, ~ ] = motionCorrectToNearestPixel( double(imG), double(imR), file, ...
                        mcorr_output.imscale, mcorr_output.Nimg_ave, mcorr_output.refChannel, mcorr_output.redoT );
        end
        
        % Save summary figure
        fh = figure; 
        subplot(221), 
            imagesc( out_g.meanframe ); 
            axis image; colorbar; axis off;
            title( 'Mean frame for raw green' );
        subplot(222), 
            imagesc( out_g.meanregframe ); 
            axis image; colorbar; axis off; 
            title( 'Mean frame for corrected green' );
        subplot(223), 
            imagesc( out_r.meanframe ); 
            axis image; colorbar; axis off; 
            title( 'Mean frame for raw red' );
        subplot(224), 
            imagesc( out_r.meanregframe ); 
            axis image; colorbar; axis off;
            title( 'Mean frame for corrected red' );
        axes('Position',[0 0 1 1],'Xlim',[0 1],'Ylim',[0  1],'Box','off',...
            'Visible','off','Units','normalized', 'clipping' , 'off');
            titletext = [file(1:8) '-' file(10:11) '.' file(13:14) '.' file(16:17)];
            text(0.5, 0.98,titletext);
        fname_fig = [filedir file '_mcorr_summary'];
            savefig( fh, fname_fig );
            saveas( fh, fname_fig(1:end-4), 'pdf' );
        close( fh );

        % Save output
        mcorr_output.green = out_g;
        mcorr_output.red = out_r;
        mcorr_output.shifts = shifts;
        mcorr_output.template = template;
        save(fname_mat_mcorr,'-struct','mcorr_output');

        % Save motion corrected tif images
        prevstr = sprintf( '%s: Saving motion corrected tif images...\n', file );
        cprintf('Text',prevstr);
            writeTifStack( imG,fname_tif_gr_mcorr );
            writeTifStack( imR,fname_tif_red_mcorr );
        str = sprintf( '%s: Motion corrected tif images saved\n', file );
        refreshdisp( str, prevstr );
    else
        yn_gr_mcorr = exist(fname_tif_gr_mcorr,'file');
        yn_red_mcorr = exist(fname_tif_red_mcorr,'file');
        yn_mat_mcorr = exist(fname_mat_mcorr,'file');
        yn_fig_mcorr = exist(fname_fig,'file');

        % If any of motion corrected tif stacks or motion correction output
        % mat doesn't exist, run motion correction
        if any([~yn_gr_mcorr,~yn_red_mcorr,~yn_mat_mcorr])
            if mcorr_method == 1
                [ imG, imR, out_g, out_r, shifts, template, ~ ] = normcorre_2ch( imG, imR, params.nonrigid );
            else
                imscale = params.imscale;
                Nimg_ave = params.Nimg_ave;
                refChannel = params.refChannel;
                redoT = params.redoT;
                [ imG, imR, out_g, out_r, shifts, template, ~ ] = motionCorrectToNearestPixel( double(imG), double(imR), file, imscale, Nimg_ave, refChannel, redoT );
            end
            
            % Save summary figure
            fh = figure; 
            subplot(221), 
                imagesc( out_g.meanframe ); 
                axis image; colorbar; axis off;
                title( 'Mean frame for raw green' );
            subplot(222), 
                imagesc( out_g.meanregframe ); 
                axis image; colorbar; axis off; 
                title( 'Mean frame for corrected green' );
            subplot(223), 
                imagesc( out_r.meanframe ); 
                axis image; colorbar; axis off; 
                title( 'Mean frame for raw red' );
            subplot(224), 
                imagesc( out_r.meanregframe ); 
                axis image; colorbar; axis off;
                title( 'Mean frame for corrected red' );
            axes('Position',[0 0 1 1],'Xlim',[0 1],'Ylim',[0  1],'Box','off',...
                'Visible','off','Units','normalized', 'clipping' , 'off');
                titletext = [file(1:8) '-' file(10:11) '.' file(13:14) '.' file(16:17)];
                text(0.5, 0.98,titletext);
            fname_fig = [filedir file '_2P_mcorr_summary'];
                savefig( fh, fname_fig );
                saveas( fh, fname_fig(1:end-4), 'pdf' );
            close( fh );

            % Save output
            mcorr_output.green = out_g;
            mcorr_output.red = out_r;
            mcorr_output.shifts = shifts;
            mcorr_output.template = template;
            save(fname_mat_mcorr,'-struct','mcorr_output');

            % Save motion corrected tif images
            prevstr = sprintf( '%s: Saving motion corrected tif images...\n', file );
            cprintf('Text',prevstr);
                writeTifStack( imG,fname_tif_gr_mcorr );
                writeTifStack( imR,fname_tif_red_mcorr );
            str = sprintf( '%s: Motion corrected tif images saved\n', file );
            refreshdisp( str, prevstr );
        else
            % If they do exist, load motion corrected tif stacks
            [imG, imR] = load_imagefile( data_locn, file, 1, '_mcorr', mcorr_method );
            mcorr_output = load(fname_mat_mcorr);
            if mcorr_method == 1
                params.nonrigid = mcorr_output.params.nonrigid; 
            else
                params.imscale = mcorr_output.params.imscale;
                params.Nimg_ave = mcorr_output.params.Nimg_ave; 
                params.refChannel = mcorr_output.params.refChannel; 
                params.redoT = mcorr_output.params.redoT; 
            end

            if ~yn_fig_mcorr
                % If summary fig doesn't exist, create it   
                out_g = mcorr_output.green;
                out_r = mcorr_output.red;
                fh = figure; 
                subplot(221), 
                    imagesc( out_g.meanframe ); 
                    axis image; colorbar; axis off;
                    title( 'Mean frame for raw green' );
                subplot(222), 
                    imagesc( out_g.meanregframe ); 
                    axis image; colorbar; axis off; 
                    title( 'Mean frame for corrected green' );
                subplot(223), 
                    imagesc( out_r.meanframe ); 
                    axis image; colorbar; axis off; 
                    title( 'Mean frame for raw red' );
                subplot(224), 
                    imagesc( out_r.meanregframe ); 
                    axis image; colorbar; axis off;
                    title( 'Mean frame for corrected red' );
                axes('Position',[0 0 1 1],'Xlim',[0 1],'Ylim',[0  1],'Box','off',...
                    'Visible','off','Units','normalized', 'clipping' , 'off');
                    titletext = [file(1:8) '-' file(10:11) '.' file(13:14) '.' file(16:17)];
                    text(0.5, 0.98,titletext);
                fname_fig = [filedir file '_mcorr_summary'];
                    savefig( fh, fname_fig );
                    saveas( fh, fname_fig(1:end-4), 'pdf' );
                close( fh );
            end
        end
    end
