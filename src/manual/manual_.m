%--------------------------------------------------------------------------
function manual_(P, vcMode)
    % display manual sorting interface
    global fDebug_ui trFet_spk

    if nargin < 2
        vcMode = 'normal';
    end % {'normal', 'debug'}

    % Load info
    if ~is_sorted_(P)
        fprintf(2, 'File must be sorted first (run "jrc spikesort %s")\n', P.vcFile_prm);
        return;
    end

    [S0, P] = load_cached_(P);
    if ~isfield(S0, 'mrPos_spk')
        S0.mrPos_spk = jrclust.utils.spikePos(S0.viSite_spk, trFet_spk, P);
        set(0, 'UserData', S0);
    end

    fDebug_ui = 0;
    P.fGpu = 0; %do not use GPU for manual use
    set0_(fDebug_ui, P);

    if strcmpi(vcMode, 'normal')
        if ~isempty(get_set_(S0, 'cS_log', {}))
            switch lower(questdlg_('Load last saved?', 'Confirmation'))
                case 'no'
                    spikeData = struct('spikeTimes', S0.viTime_spk, ...
                                       'spikeSites', S0.viSite_spk, ...
                                       'spikeSites2', S0.viSite2_spk, ...
                                       'spikePositions', S0.mrPos_spk);
                    [S_clu, S0] = jrclust.cluster.autoMerge(S0.S_clu, spikeData, P);
                    S0 = clear_log_(S0);

                case 'cancel'
                    return;

                case 'yes'
                    S0 = set0_(P); %update the P structure
                    S0.S_clu.updateWaveforms(P);
            end
        else
            S_clu = S0.S_clu;
        end
    elseif strcmpi(vcMode, 'debug')
        fDebug_ui = 1;
        S0 = set0_(fDebug_ui);
        spikeData = struct('spikeTimes', S0.viTime_spk, ...
                           'spikeSites', S0.viSite_spk, ...
                           'spikeSites2', S0.viSite2_spk, ...
                           'spikePositions', S0.mrPos_spk);
        [S_clu, S0] = jrclust.cluster.autoMerge(S0.S_clu, spikeData, P); %redo the clustering (reset to auto)
        S0 = set0_(P);
    end % if

    % Create figures
    hMsg = msgbox_('Plotting... (this closes automatically)'); t1=tic;
    set(0, 'UserData', S0);
    S0 = figures_manual_(P); %create figures for manual interface

%     clear mouse_figure;
    clear get_fig_cache_ get_tag_ %clear persistent figure handles

    % Set fields
    S0 = struct_merge_(S0, struct('iCluCopy', 1, 'iCluPaste', [], 'hCopy', [], 'hPaste', [], 'nSites', numel(P.viSite2Chan)));
    set(0, 'UserData', S0);
    
    if ~isfield(S0, 'P')
        S0.P = P;
    end
    if ~isfield(S0, 'S_clu')
        S0.S_clu = S_clu;
    end

    S0 = plot_FigRD_(S0);
    S0.S_clu = plot_FigRD_(S0.S_clu, P); % ask user before doing so

    % Set initial amplitudes
    set(0, 'UserData', S0);
    plot_FigWavCor_(S0); % hFigWavCor
    S0 = plot_FigWav_(S0); % hFigWav %do this after for ordering
    %%%%%%%%%%%%%%%%%%%%

    % hFigProj, hFigHist, hFigIsi, hFigCorr, hFigPos, hFigMap, hFigTime
    close_(get_fig_('FigTrial')); %close previous FigTrial figure
    close_(get_fig_('FigTrial_b')); %close previous FigTrial figure
    S0 = button_CluWav_simulate_(1, [], S0); %select first clu
    auto_scale_proj_time_(S0);
    S0 = keyPressFcn_cell_(get_fig_cache_('FigWav'), {'z'}, S0); %zoom
    %S0.cS_log = load_(strrep(P.vcFile_prm, '.prm', '_log.mat'), 'cS_log', 0);
    S_log = load_(strrep(P.vcFile_prm, '.prm', '_log.mat'), [], 0);

    if ~isempty(S_log)
        S0.cS_log = {S_log};
    end
    save_log_('start', S0); %crash proof log

    % Finish up
    close_(hMsg);
    fprintf('UI creation took %0.1fs\n', toc(t1));
end %func
