function success = autoMerge(obj)
%AUTOMERGE Automatically merge clusters.
for iRepeat = 1:obj.hCfg.nPassesMerge % single-pass vs dual-pass correction
    nMerged = obj.mergeBySim();

    if nMerged < 1
        break;
    end
end

success = 1;
end %fun
