classdef (Abstract) Clustering < handle
    %CLUSTERING A clustering of spike data
    %% CONFIGURATION
    properties (Hidden, SetObservable)
        hCfg;               % Config object
    end

    %% CLASS INTROSPECTION
    properties (SetAccess=protected, Hidden)
        unitFields;         % data fields related to clusters
    end

    %% DETECTION/SORTING RESULTS
    properties (Hidden, SetObservable)
        dRes;               % detection results
        sRes;               % sorting results
    end

    %% DETECTION RESULTS (IMMUTABLE)
    properties (Dependent, Transient)
        detectedOn;         % timestamp, when spikes were detected
        nSpikes;            % number of spikes detected
    end

    %% SORTING DATA (MUTABLE)
    properties (SetObservable)
        clusterCentroids;   % centroids of clusters on the probe
        clusterNotes;       % notes on clusters
        clusterSites;       % mode site per cluster
        history;            % cell array, log of merge/split/delete operations
        meanWfGlobal;       % mean filtered waveforms for each cluster over all sites
        meanWfGlobalRaw;    % mean raw waveforms for each cluster over all sites
        meanWfLocal;        % mean filtered waveforms for each cluster
        meanWfLocalRaw;     % mean raw waveforms for each cluster
        meanWfRawLow;       % mean raw waveforms for each cluster over all sites at a low point on the probe (for drift correction)
        meanWfRawHigh;      % mean raw waveforms for each cluster over all sites at a high point on the probe (for drift correction)
        spikeClusters;      % individual spike assignments
        spikesByCluster;    % cell array of spike indices per cluster
        waveformSim;        % cluster similarity scores
    end
    
    % properties which should not be saved, but need to be alterable by
    % test classes
    properties (Hidden)
        recompute;          % indices of units with metadata to recompute
    end

    % computed from other values, but only on set
    properties (SetAccess=protected, Transient)
        nClusters;          % number of clusters
    end

    % computed from other values
    properties (Dependent, Transient)
        annotatedOnly;      % IDs of units which have annotations
        nEdits;             % number of edits made to initial clustering
        unitCount;          % number of spikes per cluster
    end

    %% QUALITY METRICS
    properties (SetObservable)
        unitPeaks;          % minimum voltage of mean filtered waveforms at peak site, per cluster
        unitPeaksRaw;       % minimum voltage (uV) of mean raw waveforms at peak site, per cluster
        unitPeakSites;      % sites on which unitPeaks occur
        unitVpp;            % peak-to-peak voltage of filtered waveforms at peak site, per cluster
        unitVppRaw;         % peak-to-peak voltage of raw waveforms at peak site, per cluster
        unitISIRatio;       % inter-spike interval ratio #(ISI <= 2ms)/#(ISI <= 20ms), per cluster
        unitIsoDist;        % isolation distance
        unitLRatio;         % L-ratio
    end

    %% SORTING RESULTS (IMMUTABLE)
    properties (Dependent, Transient)
        initialClustering;  % initial assignment of spikes to cluster
    end

    %% DETECTION RESULTS (IMMUTABLE)
    properties (Dependent, Transient)
        spikeAmps;          % amplitudes of detected spikes
        spikePositions;     % positions on the probe at which spikes are detected
        spikeSites;         % sites on which spikes occur
        spikeTimes;         % times at which spikes occurred

        spikesBySite;       % aggregate of spike indices by site

        spikesRaw;          % raw spike traces
        spikesFilt;         % filtered spike traces
        spikeFeatures;      % features which were clustered
    end

    %% CACHED VALUES
    properties (Transient)
        spikesFiltVolt;     % spikesFilt in units of microvolts
        spikesRawVolt;      % spikesRaw in units of microvolts
    end

    %% LIFECYCLE
    methods
        function obj = Clustering(hCfg, sRes, dRes)
            %CLUSTERING Construct an instance of this class
            fid = fopen(fullfile(jrclust.utils.basedir(), 'json', 'Clustering.json'), 'r');
            obj.unitFields = jsondecode(fread(fid, inf, '*char')');
            fclose(fid);

            % get specific fields for this subclass
            clsSplit = strsplit(class(obj), '.');
            clsName = clsSplit{end}; % e.g., jrclust.sort.DensityPeakClustering -> DensityPeakClustering

            fieldFile = fullfile(jrclust.utils.basedir(), 'json', [clsName, '.json']);
            if exist(fieldFile, 'file') == 2
                fid = fopen(fieldFile, 'r');
                specificFields = jsondecode(fread(fid, inf, '*char')');
                fclose(fid);

                if isfield(specificFields, 'vectorFields')
                    obj.unitFields.vectorFields = [obj.unitFields.vectorFields; specificFields.vectorFields];
                end
                if isfield(specificFields, 'otherFields')
                    obj.unitFields.otherFields = jrclust.utils.mergeStructs(obj.unitFields.otherFields, specificFields.otherFields);
                end
            end

            % set sRes, dRes, and hCfg
            if nargin < 2
                sRes = struct();
            end
            if nargin < 3
                dRes = struct();
            end

            obj.hCfg = hCfg;
            obj.dRes = dRes;
            obj.sRes = sRes;

            if isfield(sRes, 'spikeClusters')
                % these fields are mutable so we need to store copies in obj
                obj.spikeClusters = obj.initialClustering;

                if isfield(sRes, 'spikesByCluster')
                    obj.spikesByCluster = sRes.spikesByCluster;
                else
                    obj.spikesByCluster = arrayfun(@(iC) find(sRes.spikeClusters == iC), (1:max(sRes.spikeClusters))', 'UniformOutput', 0);
                end

                if isfield(sRes, 'clusterCentroids')
                    obj.clusterCentroids = sRes.clusterCentroids;
                end

                if isfield(sRes, 'clusterSites')
                    obj.clusterSites = sRes.clusterSites;
                end
            end

            obj.history = struct('optype', cell(1), 'message', cell(1), 'indices', cell(1));
            obj.recompute = [];
        end
    end

    %% ABSTRACT METHODS
    methods (Abstract)
        success = exportQualityScores(obj, zeroIndex, fGui);
        rmOutlierSpikes(obj);
    end

    %% UTILITY METHODS
    methods (Access=protected, Hidden)
        [sites1, sites2, sites3] = getSecondaryPeaks(obj);
        nMerged = mergeBySim(obj);
        removeEmptyClusters(obj);
    end

    %% GETTERS/SETTERS
    methods
        % annotatedOnly
        function val = get.annotatedOnly(obj)
            if iscell(obj.clusterNotes)
                val = find(cellfun(@(c) ~isempty(c), obj.clusterNotes));
            else
                val = [];
            end
        end

        % detectedOn
        function val = get.detectedOn(obj)
            if isfield(obj.sRes, 'detectedOn')
                val = obj.sRes.detectedOn;
            else
                val = now();
            end
        end
        function set.detectedOn(obj, val)
            obj.sRes.detectedOn = val;
        end

        % hCfg
        function set.hCfg(obj, hc)
            failMsg = 'hCfg must be an object of type jrclust.Config';
            assert(isa(hc, 'jrclust.Config'), failMsg);
            obj.hCfg = hc;
        end

        % initialClustering
        function ic = get.initialClustering(obj)
            if isfield(obj.sRes, 'spikeClusters')
                ic = obj.sRes.spikeClusters;
            else
                ic = [];
            end
        end
        function set.initialClustering(obj, val)
            obj.sRes.spikeClusters = val;
        end

        % nEdits
        function ne = get.nEdits(obj)
            ne = numel(obj.history.message);
        end

        % nSpikes
        function val = get.nSpikes(obj)
            val = numel(obj.spikeTimes);
        end

        % spikeAmps
        function sa = get.spikeAmps(obj)
            if isfield(obj.dRes, 'spikeAmps')
                sa = obj.dRes.spikeAmps;
            else
                sa = [];
            end
        end
        function set.spikeAmps(obj, val)
            obj.dRes.spikeAmps = val;
        end

        % spikeClusters
        function set.spikeClusters(obj, sc)
            obj.spikeClusters = sc;
            obj.nClusters = numel(unique(sc(sc > 0))); %#ok<MCSUP>
        end

        % spikeFeatures
        function set.spikeFeatures(obj, sf)
            obj.dRes.spikeFeatures = sf;
        end
        function sf = get.spikeFeatures(obj)
            if isfield(obj.dRes, 'spikeFeatures')
                sf = obj.dRes.spikeFeatures;
            else
                sf = [];
            end
        end

        % spikePositions
        function sf = get.spikePositions(obj)
            if isfield(obj.dRes, 'spikePositions')
                sf = obj.dRes.spikePositions;
            else
                sf = [];
            end
        end
        function set.spikePositions(obj, val)
            obj.dRes.spikePositions = val;
        end

        % spikesBySite
        function ss = get.spikesBySite(obj)
            if isfield(obj.dRes, 'spikesBySite')
                ss = obj.dRes.spikesBySite;
            else
                ss = [];
            end
        end
        function set.spikesBySite(obj, val)
            obj.dRes.spikesBySite = val;
        end

        % spikesFilt
        function set.spikesFilt(obj, sf)
            obj.dRes.spikesFilt = sf;
        end
        function sf = get.spikesFilt(obj)
            if isfield(obj.dRes, 'spikesFilt')
                sf = obj.dRes.spikesFilt;
            else
                sf = [];
            end
        end

        % spikeSites
        function ss = get.spikeSites(obj)
            if isfield(obj.dRes, 'spikeSites')
                ss = obj.dRes.spikeSites;
            else
                ss = [];
            end
        end
        function set.spikeSites(obj, val)
            obj.dRes.spikeSites = val;
        end

        % spikesRaw
        function set.spikesRaw(obj, sr)
            obj.dRes.spikesRaw = sr;
        end
        function sr = get.spikesRaw(obj)
            if isfield(obj.dRes, 'spikesRaw')
                sr = obj.dRes.spikesRaw;
            else
                sr = [];
            end
        end

        % spikeTimes
        function val = get.spikeTimes(obj)
            if isfield(obj.dRes, 'spikeTimes')
                val = obj.dRes.spikeTimes;
            else
                val = [];
            end
        end
        function set.spikeTimes(obj, val)
            obj.dRes.spikeTimes = val;
        end
        
        % unitCount
        function val = get.unitCount(obj)
            if iscell(obj.spikesByCluster)
                val = cellfun(@numel, obj.spikesByCluster);
            else
                val = [];
            end
        end
    end
end
