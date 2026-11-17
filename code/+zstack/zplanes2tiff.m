function [out, channels, meta] = zplanes2tiff(fname, chan, outFiles, varargin)
% Build a fully-registered z-stack and save one TIFF per channel.
%
% function [out, channels, meta] = zstack.zplanes2tiff(fname, chan, outFiles, Name=Value)
%
% Purpose
% Runs zstack.zplanes2stack, then saves each channel of the result as a
% signed 16-bit TIFF with zstack.io.writeSignedTiff. The metadata returned
% by zplanes2stack, plus zplanes2stack.derived.channel giving the channel
% that file holds, is saved twice for each file: as "name = value" lines in
% the TIFF's Software tag, and as a JSON file with the same name as the
% TIFF (e.g. green.json next to green.tiff).
%
% The output file names are checked before registration starts, so a
% mistake there doesn't waste a long run.
%
% Each run is logged: everything printed to the command window goes to
% zplanes2tiff_<date>_<time>.log in the folder of the first output file.
% The log starts with this toolbox's git commit (flagging uncommitted
% changes) and ends with one line giving the result: SUCCESS, FAILED
% (nothing saved; the reason is printed above it) or ERROR (followed by the
% error being raised as usual). A diary you already had running is paused
% for the run and resumed afterwards.
%
% Inputs
% fname - relative or absolute path to a ScanImage TIFF stack on disk.
% chan - the channel used to calculate the registration.
% outFiles - cell array of output file names, one per saved channel, in the
%            order ScanImage saved them (its channelSave setting). Neither
%            these files nor their JSON files may already exist.
%
% Optional name-value arguments
% Passed on to zstack.zplanes2stack; see its help.
%
% Outputs
% out, channels, meta - as returned by zstack.zplanes2stack.
%
% Examples
%
% - Register on channel 2 and save channels 1 and 2 as red and green
% >> zstack.zplanes2tiff('file_00001.tif', 2, {'red.tiff', 'green.tiff'}, 'sigma', 2, 'refine', true);
arguments
    fname {mustBeFile}
    chan % validated by zplanes2stack
    outFiles cell
end
arguments (Repeating)
    varargin % name-value arguments, passed on to zplanes2stack
end

out = []; % in case of an error
channels = [];
meta = struct();

% Refuse output folders that don't exist before anything else. The log goes
% in the first one, and a missing folder would otherwise only fail at the
% save, after registration.
outFolders = unique(cellfun(@fileparts, outFiles, 'UniformOutput', false));
outFolders = outFolders(~cellfun(@isempty, outFolders));
missingFolders = outFolders(~cellfun(@isfolder, outFolders));
if ~isempty(missingFolders)
    fprintf('Output folder does not exist: %s\n', missingFolders{:})
    return
end

% Log everything printed during the run to a timestamped file beside the
% first output. The diary is global, so pause any diary already running and
% resume it when this function exits, even after an error.
logFile = fullfile(fileparts(outFiles{1}), ...
    ['zplanes2tiff_' char(datetime('now', 'Format', 'yyyy-MM-dd_HHmmss')) '.log']);
previousState = get(0, 'Diary');
previousFile = get(0, 'DiaryFile');
cleanupObj = onCleanup(@() resumeDiary(previousState, previousFile));
diary(logFile)

[~, host] = system('hostname');
fprintf('zplanes2tiff started %s on %s, MATLAB %s\n', char(datetime('now')), strtrim(host), version)

% Record which version of this toolbox did the work. git may not be
% installed (e.g. on a Windows rig), so fall back to 'unknown'.
% MATLAB's gitrepo would avoid needing the git program, but it is only
% available from R2023b.
toolboxRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
[status, commit] = system(sprintf('git -C "%s" rev-parse --short HEAD', toolboxRoot));
if status == 0
    commit = strtrim(commit);
    [~, changes] = system(sprintf('git -C "%s" status --porcelain --untracked-files=no', toolboxRoot));
    if ~isempty(strtrim(changes))
        commit = [commit ' (with uncommitted changes)'];
    end
else
    commit = 'unknown (git not available)';
end
fprintf('Toolbox commit: %s\n', commit)
fprintf('Input: %s, chan %d, outputs: %s\n', fname, chan, strjoin(outFiles, ', '))
startTime = tic;
elapsed = @() char(duration(0, 0, toc(startTime), 'Format', 'hh:mm:ss'));

% Do the work, recording any error in the log before raising it as usual
try
    [out, channels, meta] = registerAndSave(fname, chan, outFiles, varargin{:});
catch ME
    % List the stack only down to this function: frames below it belong to
    % whatever called zplanes2tiff, and say nothing about why the run failed.
    fprintf('Error: %s\n', ME.message)
    for ii = 1:length(ME.stack)
        fprintf('  in %s (line %d)\n', ME.stack(ii).name, ME.stack(ii).line)
        if endsWith(ME.stack(ii).name, 'zplanes2tiff')
            break
        end
    end
    fprintf('Result: ERROR - %s (%s)\n', ME.message, elapsed())
    rethrow(ME)
end

if isempty(out)
    fprintf('Result: FAILED - nothing saved, see messages above (%s)\n', elapsed())
else
    fprintf('Result: SUCCESS - saved %s (%s)\n', strjoin(outFiles, ', '), elapsed())
end

end % zplanes2tiff


function [out, channels, meta] = registerAndSave(fname, chan, outFiles, varargin)
% Check the outputs, register the stack and save one TIFF and JSON file per
% channel. Returns empty outputs, after printing why, if nothing was saved.

out = [];
channels = [];
meta = struct();

% Check the output files before the long registration step
metadata = zstack.io.read_SI_TIFF_header(fname);
nChannels = length(metadata.channelSave);
if length(outFiles) ~= nChannels
    fprintf('%d output files given, but the stack has %d saved channels\n', ...
        length(outFiles), nChannels)
    return
end

% Each TIFF's JSON file has the same name, with the extension .json
jsonFiles = cell(size(outFiles));
for k = 1:length(outFiles)
    [folder, name] = fileparts(outFiles{k});
    jsonFiles{k} = fullfile(folder, [name '.json']);
end

existing = [outFiles(:); jsonFiles(:)];
existing = existing(cellfun(@isfile, existing));
if ~isempty(existing)
    fprintf('Output file already exists: %s\n', existing{:})
    return
end

[out, channels, meta] = zstack.zplanes2stack(fname, chan, varargin{:});
if isempty(out)
    return
end

% Save each channel with its metadata, adding the channel number, both in
% the TIFF's Software tag and as a JSON file
for k = 1:length(channels)
    metaK = meta;
    metaK.zplanes2stack.derived.channel = channels(k);

    fprintf('Saving channel %d to %s and %s\n', channels(k), outFiles{k}, jsonFiles{k})
    zstack.io.writeSignedTiff(out(:,:,:,k), outFiles{k}, meta2text(metaK, ''))

    fid = fopen(jsonFiles{k}, 'w');
    fprintf(fid, '%s\n', jsonencode(metaK, 'PrettyPrint', true)); % PrettyPrint needs R2021a
    fclose(fid);
end

end % registerAndSave


function txt = meta2text(s, prefix)
% Write a metadata struct as "name = value" lines, one per field. Nested
% structs give dotted names, e.g. SI.hStackManager.numSlices = 350
txt = '';
for f = fieldnames(s)'
    name = [prefix f{1}];
    value = s.(f{1});
    if isstruct(value)
        txt = [txt meta2text(value, [name '.'])]; %#ok<AGROW>
    else
        txt = [txt sprintf('%s = %s\n', name, mat2str(value))]; %#ok<AGROW>
    end
end

end % meta2text


function resumeDiary(previousState, previousFile)
% Stop this run's log and resume the diary that was running before, if any
diary('off')
set(0, 'DiaryFile', previousFile)
if strcmp(previousState, 'on')
    diary('on')
end

end % resumeDiary
