% Written by Ann Go

function parsave(fname_allData,file,mcorr_output,tsG,tsR,masks,mean_imratio,R,spikes,...
                        fname_track,occMap,spikeMap,infoMap,placeMap,downData,activeData,...
                        placeMap_smooth,sorted_placeMap,sortIdx,params)
   
    save(fname_allData,'file','mcorr_output','tsG','tsR','masks','mean_imratio','R','spikes',...
                    'fname_track','occMap','spikeMap','infoMap','placeMap','downData','activeData',...
                    'placeMap_smooth','sorted_placeMap','sortIdx','params');

end