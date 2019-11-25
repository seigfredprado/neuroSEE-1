function params_def = load_defaultparams( params )

    params_def = load( 'default_params.mat' );
    
    % Remove irrelevant parameters 
    if strcmpi(params.methods.mcorr_method,'normcorre')
        params_def = rmfield(params,'fftRigid');
        fields = {'df_prctile','df_medfilt1'};
        params_def.ROIsegment = rmfield(params_def.ROIsegment,fields);
    else
        params_def = rmfield(params_def,'nonrigid');
    end
    
    if ~params.methods.dofissa
        params_def = rmfield(params_def,'fissa');
    end
    
    params_def.methods = params.methods;
