function [out, channels, meta, slices] = zplanes2stack(fname, chan, opts)
% Build a fully-registered z-stack from a multi-plane series.
%
% function [out, channels, meta, slices] = zstack.zplanes2stack(fname, chan, Name=Value)
%
% Purpose
% Feed in an unregistered set of z-planes in ZTCYX format (e.g., such that
% for a 2-channel series the pages would be ordered
% [z1t1c1, z1t1c2, z1t2c1, z1t2c2, ... , z2t1c1, ... ] so on and so forth.
% Register *within* each z-plane, averaging over time to produce a mean
% frame. Register *between* each z-plane to produce a coherent z-stack.
% Registration is conducted using the named channel `chan`, and the
% registration coefficients obtained from the named channels are then
% applied to the remaining channels, so all channels stay in register with
% one another.
%
% Optionally the data may be high-pass filtered as they are loaded, before
% anything else touches them. This is off by default. Filtering here rather
% than within the registration keeps all channels treated identically.
%
% Additional refinement and blurring options are available to improve the
% registration step for noisy data. See the `register_plane` function for
% details.
%
% If bidirectional scanning correction is required, set
% needsBidiCorrection=true. This will calculate the required shift (up to
% +-9 pixels) and apply it to the stack before registration.
%
% Inputs
% fname - relative or absolute path to a ScanImage TIFF stack on disk.
% chan - the channel used to calculate the registration.
%
% Optional name-value arguments
% freq_cutoff - frequency threshold in cycles per image for the
%               high-pass filter applied to each channel. If zero no
%               filtering is done, which is the default. A value of about
%               0.015 filters very low frequencies. The filter is not enabled
%               by default because it needs more work.
% refine      - boolean flag to indicate whether to refine the 
%               registration using the mean of the registered frames.
%               Default: false.
% sigma       - standard deviation of Gaussian filter to apply to
%               the frames during registration. Default: 0 (no filtering).
% needsBidiCorrection - boolean flag to indicate whether the
%                       image stack requires bidirectional scanning correction.
%                       Default: false.
% Outputs
% out - a 4D array (Y, X, Z, channel) containing the registered z-stack.
% channels - a 1D array containing the channel numbers corresponding to the
%            4th dimension of `out`.
% meta - a struct of metadata describing `out`, with fields:
%        - SI: acquisition settings that apply to every channel, copied
%          from the ScanImage header and nested as ScanImage names them
%          (e.g. meta.SI.hStackManager.numSlices). Per-channel settings
%          (e.g. channel offsets, PMT gains) are not included. Any
%          requested field not found in the ScanImage header is named in
%          the command window and left out.
%        - epoch: the acquisition date and time, from the first frame's
%          ImageDescription.
%        - zplanes2stack.input: the inputs to this function.
%        - zplanes2stack.derived: values describing `out`: the slices
%          kept, the edge crop, the pixel size and the bidirectional shift
%          applied.
%        zstack.zplanes2tiff saves `out` with this metadata, both in each
%        TIFF's Software tag and as a JSON file.
% slices - a table with one row per slice kept, with columns:
%          slice - the slice number.
%          zUm - z position of the slice's first frame, relative to the
%                start of the stack, from ScanImage's per-frame list
%                (SI.hStackManager.zs). NaN if the header doesn't have it.
%          shiftXPx, shiftYPx - the total shift applied to the slice to bring
%                it into line with slice 1. Each slice is registered to the
%                previous slice after that slice was itself shifted, so these
%                accumulate down the stack and include any steady drift.
%          stepXPx, stepYPx - the slice's shift minus the previous slice's:
%                how far it moved from its neighbour. A step longer than
%                10 px is also reported in the command window, as it may be
%                a wrong match rather than real movement.
%          framesAtZeroShiftWithinSlice - frames given exactly zero shift
%                by the *within*-slice registration (frames to the slice's
%                reference), unlike the shift and step columns, which are
%                *between* slices. Many or all frames at zero *may* be
%                indicative of a poor registration (low signal-to-noise ratio;
%                registration "stuck" at 0), but is also expected when the
%                sample legitimately barely moved. The poor registration
%                problem is most often observed with sigma = 0; rerun with a
%                different sigma and compare results if necessary.
%          zstack.zplanes2tiff saves this as a .csv or .tsv file.
%
% Examples
%
% - Register on channel 1 with no filtering
% >> OUT = zstack.zplanes2stack('myUnregisteredZstack.tif',1);
%
% - The same, but high-pass filter the data first
% >> OUT = zstack.zplanes2stack('myUnregisteredZstack.tif',1,freq_cutoff=0.015);
%
% - To register and save one TIFF per channel with its metadata, see
%   zstack.zplanes2tiff
arguments
    fname {mustBeFile}
    chan (1, 1) {mustBeInteger, mustBePositive}
    opts.freq_cutoff (1, 1) double {mustBeNonnegative} = 0
    opts.refine (1, 1) logical = false
    opts.sigma (1, 1) double {mustBeNonnegative} = 0
    opts.needsBidiCorrection (1, 1) logical = false
end

% Record all argument values (including defaults) in the command window.
fprintf('zplanes2stack: %s, chan %d\n', fname, chan); disp(opts)

% In case of an error
out = [];
channels = [];
meta = struct();
slices = table();

% Preemptively promote fname to a cell array in case our stack is split
% across multiple files.
fname = {fname};

%% Open TIFF and collect ScanImage metadata
%  We read both the 'Software' tag, containing metadata for the entire acquisition,
%  as well as the *first* frame's 'ImageDescription'. We need the latter so that
%  we can extract the acquisition date (which is per-frame, but one will do).
t = Tiff(fname{1});
metadata = zstack.io.read_SI_TIFF_header(t);
siHeader = t.getTag('Software');
frameDesc = t.getTag('ImageDescription');

% Append ImageWidth and ImageLength tags to metadata.
% These are mandatory TIFF tags; not part of the Software tag that
% ScanImage writes to.
metadata.ImageWidth = t.getTag('ImageWidth');
metadata.ImageLength = t.getTag('ImageLength');

savedChannelID = metadata.channelSave; % The indices of the saved channels

% Confirm we can return the desired depth and channel
if ~any(savedChannelID==chan)
    fprintf('Channel %d does not exist in this stack\n', chan)
    return
end

% Find the index of the channel to be used for registration
chan_idx = find(savedChannelID == chan);
if length(chan_idx) > 1
    fprintf('There are duplicate entries for the requested Channel %d in this stack\n', chan)
    return
end

nChannels = length(savedChannelID);

% Check each of:
% - How many z-slices are in our stack
% - How many frames are in each slice
% - How many frames are written to each file

nZslices=metadata.numSlices;
framesPerSlice = metadata.framesPerSlice; % TODO: potentially divide by logAverageFactor here
logFramesPerFile = metadata.logFramesPerFile;

% Check whether stack is split across multiple files.
if nZslices * framesPerSlice > logFramesPerFile

    % Find all files matching pattern.
    % We assume this is a sequence like:
    % file_00001_00001.tif, file_00001_00002.tif, ...
    [d, name, ext] = fileparts(fname{1});
    prefix = regexprep(name, '\d+$', '');
    f = dir(fullfile(d, [prefix '*' ext]));
    names = sort({f.name});
    files = fullfile(d, names(matches(names, prefix + digitsPattern + ext)));

    if ~strcmp(files{1}, fullfile(d, [name ext]))
        fprintf('%s is not the first file in its sequence.\n', fname{1});
        return
    end

    % ScanImage starts a new file every logFramesPerFile frames, so we can
    % tell if any are missing (or if the acquisition stopped early).
    nFilesExpected = ceil(nZslices * framesPerSlice / logFramesPerFile);
    if length(files) < nFilesExpected
        fprintf('Found %d of %d expected files; the acquisition may have stopped early, or files are missing.\n', ...
            length(files), nFilesExpected)
    end

    fname = files;

end

%% Count pages
% Run a preliminary check to count the pages in each file and see if we can
% recover the total number of slices as stated in the metadata.
% Every file except (potentially) the last should be full; pages after a
% short file can't be assigned to slices, so stop counting there.
nPages = 0;
for ff = 1:length(fname)
    
    tf = Tiff(fname{ff});
    
    % Count all pages in current TIFF.
    n = 1;
    while ~tf.lastDirectory()
        tf.nextDirectory();
        n = n + 1;
    end
    
    % Close TIFF and record pages counted.
    tf.close();
    nPages = nPages + n;
    
    % If number of pages in TIFF does not constitute a complete file,
    % break early.
    if n < logFramesPerFile*nChannels
        break
    end

end

% Truncate data (and warn) if fewer slices than stated in metadata.
nComplete = floor(nPages / (framesPerSlice*nChannels));
if nComplete < nZslices
    fprintf('Data end in file %d of %d: only the first %d of %d slices are complete.\n', ...
        ff, length(fname), nComplete, nZslices)
    
    % Truncate number of zslices and files list to however many we were
    % able to successfully read.
    nZslices = nComplete;
    fname = fname(1:ff);
end

%% Load stack and register within slices
% Two problems with our stack:
% - It is split over multiple files
% - It is too large for memory
%
% Loop through slices and files and perform registration on each slice.
% Store *registered* slices in a new 4D array (small memory footprint).
% Registration within a slice is incremental, so we can do away with old
% pages once we've read them.

% Find shifts for bidirectional scanning correction, if requested.
bidishiftpixels = 0;
if opts.needsBidiCorrection
        
    fprintf('Calculating shift required for bidirectional scanning correction.\n')

    % Grab a TIFF from about half way through the stack.
    % Use ceil to avoid a 0 index if we have only one file.
    bidiFile = ceil(length(fname)/2);
    tf = Tiff(fname{bidiFile});

    % Make sure we use the correct channel
    n = 1;
    while ~tf.lastDirectory() && n ~= chan_idx
        tf.nextDirectory();
        n = n + 1;
    end

    % Read up to 10 frames
    bidiFrames = zeros( ...
        metadata.ImageLength, ...
        metadata.ImageWidth, ...
        10, ...
        'double' ...
        );

    n = 0;
    while ~tf.lastDirectory() && n < 10
        
        n = n + 1;
        bidiFrames(:, :, n) = tf.read();

        for ii = 1:nChannels
            if ~tf.lastDirectory()
                tf.nextDirectory();
            end
        end

    end

    % If we read fewer than 10 frames, drop data to avoid including in mean
    bidiFrames = bidiFrames(:, :, 1:n);

    % Calculate shifts on even lines of the averaged image.
    meanBidiFrame = mean(bidiFrames, 3);
    [~, stats] = zstack.bidi.getShift(meanBidiFrame, metadata, true, true);

    bidishiftpixels = stats.shiftAmnt;

    if ~isnan(bidishiftpixels)
        fprintf('Shift is %d\n', bidishiftpixels)
    else
        fprintf('No meaningful shift calculated\n')
        bidishiftpixels = 0;
    end

    tf.close();

end

% Calculate edge cropping
cropEdgePixels = round(metadata.ImageWidth*0.058);
uncroppedCols = cropEdgePixels + 1 : metadata.ImageWidth - cropEdgePixels;

% Preallocate outStack. This contains the averaged and registered
% zslices, but without registration between slices (yet). The width has
% been cropped.
outStack = zeros( ...
    metadata.ImageLength, ...
    length(uncroppedCols), ...
    nZslices, ...
    nChannels, ...
    'int16' ...
    );

% Preallocate reg_coeffs struct array.
% We don't currently output these and could discard them after processing
% each slice, but holding onto them will potentially be useful for
% debugging.
reg_coeffs = repmat(struct('diffPhase', 0, 'OffsetPixel', [0 0]), framesPerSlice, nZslices);

% File iterator; start at 1 because we've already loaded the first TIFF.
fileCount = 1;

% Start timer for ETA reporting.
tic

for ii = 1:nZslices % Z

    fprintf('Registering slice %d of %d\n', ii, nZslices);

    % Preallocate array to hold data from TIFF for this z-slice.
    % Use 'int16', consistent with expected data type from TIFF.
    % The width has not yet been cropped; we read complete images from the
    % TIFF and crop them below.
    thisZslice = zeros( ...
        metadata.ImageLength, ...
        metadata.ImageWidth, ...
        framesPerSlice, ...
        nChannels, ...
        'int16' ...
        );
    
    for jj = 1:framesPerSlice % T
        for kk = 1:nChannels % C

            thisZslice(:, :, jj, kk) = t.read();
            if ~t.lastDirectory()
                t.nextDirectory();
            else
                t.close();
                if fileCount < length(fname)
                    fileCount = fileCount + 1;
                    t = Tiff(fname{fileCount});
                end
            end

        end
    end

    % Apply bidirectional scanning correction to even lines.
    if bidishiftpixels ~= 0
        evenRows = thisZslice(2:2:end,:,:,:);
        evenRows = circshift(evenRows,[0, bidishiftpixels, 0, 0]);
        thisZslice(2:2:end,:,:,:) = evenRows;
    end

    % Crop artefacts from image edges.
    thisZslice = thisZslice(:, uncroppedCols,  :, :);

    % Apply filtering to all channels
    if opts.freq_cutoff > 0
        for kk = 1:nChannels
            thisZslice(:, :, :, kk) = zstack.filtering.suppressLowFreq(thisZslice(:, :, :, kk), opts.freq_cutoff);
        end
    end

    % Perform registration on chosen channel.
    % Store the registration parameters to be applied to the other channels.
    [registeredChannel, reg_params_out] = zstack.registration.register_plane( ...
        thisZslice(:, :, :, chan_idx), ...
        opts.refine, ...
        opts.sigma ...
        );
    outStack(:, :, ii, chan_idx) = int16(mean(registeredChannel, 3));
    reg_coeffs(:,ii) = reg_params_out.coef;

    % Apply registration to remaining channels (if required)
    for kk = 1:nChannels

        if kk == chan_idx
            % Skip the channel originally used for registration
            continue
        end

        registeredChannel = zstack.registration.apply_ffttrans(thisZslice(:, :, :, kk), reg_coeffs(:,ii));
        outStack(:, :, ii, kk) = int16(mean(registeredChannel, 3));
    end

    % ETA
    elapsed = toc;
    remaining = elapsed/ii*(nZslices-ii);
    fprintf('   %.1f s elapsed   ETA %.1f s\n',elapsed,remaining);

end

fprintf('Continuing with registration between slices...\n')

%% Register between slices
% This has been adapted from Oliver's register_zstack_to_previous.m

% The [x y] shift applied to each slice, relative to slice 1, for the slice table
shifts = zeros(nZslices, 2);

for ii = 2:nZslices

    % Using the same registration channel, register each slice to the
    % previous one. Since the previous slice has already been shifted
    % into line with slice 1, shifts accumulate down the stack and
    % this slice's shift is also relative to slice 1. 
    % The step from the previous slice's shift is how far this slice
    % moved from its neighbour.
    tform = imregcorr(outStack(:, :, ii, chan_idx), outStack(:, :, ii-1, chan_idx), 'translation');

    % Record the shift, and report a large step from the previous slice: it
    % may be a wrong match rather than real movement.
    shifts(ii, :) = transformPointsForward(tform, [0 0]);
    step = norm(shifts(ii, :) - shifts(ii-1, :));
    if step > 10
        fprintf('Slice %d moved %.1f px from slice %d; check it by eye.\n', ii, step, ii-1)
    end

    % Apply the same transform to every channel.
    for kk = 1:nChannels
        current = outStack(:, :, ii, kk);
        outStack(:, :, ii, kk) = imwarp( ...
            current, ...
            tform, ...
            'OutputView', imref2d([metadata.ImageLength, length(uncroppedCols)]), ...
            'FillValues', median(current(:)) ...
            );
    end

end

%% Build the metadata for the saved TIFFs
% Copy a short list of acquisition settings from the ScanImage header. These
% apply to every channel, so the same metadata can go into each channel's file.
siFields = { ...
    'SI.VERSION_MAJOR', ...
    'SI.VERSION_MINOR', ...
    'SI.hStackManager.numSlices', ...
    'SI.hStackManager.actualStackZStepSize', ...
    'SI.hStackManager.framesPerSlice', ...
    'SI.hScan2D.logAverageFactor', ...
    'SI.hScan2D.bidirectional', ...
    'SI.hRoiManager.pixelsPerLine', ...
    'SI.hRoiManager.linesPerFrame', ...
    'SI.hRoiManager.scanZoomFactor', ...
    'SI.hRoiManager.scanFrameRate', ...
    'SI.hRoiManager.imagingFovUm', ...
    'SI.hMotors.axesPosition', ...
    'SI.hStackManager.stackStartPowerFraction', ...
    'SI.hStackManager.stackEndPowerFraction', ...
    };
siLines = splitlines(siHeader);
siLines = siLines(startsWith(siLines, append(siFields, ' = ')));

% The acquisition date is per-frame data, so it comes from the first frame's
% ImageDescription rather than the Software tag.
epochLine = splitlines(frameDesc);
epochLine = epochLine(startsWith(epochLine, 'epoch = '));

% Name any requested field that wasn't found.
% E.g., to catch any potential renaming of fields between different
% versions of ScanImage and report this problem to the user.
missing = setdiff(siFields, extractBefore(siLines, ' = '), 'stable');
if isempty(epochLine)
    missing{end+1} = 'epoch';
end
if ~isempty(missing)
    fprintf('The following were not present in the ScanImage header and have not been saved: %s\n', strjoin(missing(:)', ', '))
end

% Store each "SI.a.b = value" line as meta.SI.a.b, converting the value text
% as read_SI_TIFF_header does. The acquisition date goes in as meta.epoch.
% We do this conversion so that the metadata can be easily saved as a JSON
% file using jsonencode (which supports structs out-of-the-box).
for ii = 1:length(siLines)
    [name, value] = parseHeaderLine(siLines{ii});
    parts = strsplit(name, '.');
    meta = setfield(meta, parts{:}, value);
end
if ~isempty(epochLine)
    [~, meta.epoch] = parseHeaderLine(epochLine{1});
end

% Then add the inputs to this function, named as its arguments, so the run
% can be repeated.
meta.zplanes2stack.input.chan = chan;
for f = fieldnames(opts)'
    meta.zplanes2stack.input.(f{1}) = opts.(f{1});
end

% Finally add values derived during the run, which describe `out` rather
% than the raw data. The number of slices kept differs from numSlices if the
% acquisition stopped early, and the image width differs from pixelsPerLine
% because of the edge crop. Pixel size is the FOV (corners in microns)
% divided by the uncropped size.
fov = metadata.imagingFovUm;
pixelSizeUm = [ ...
    (max(fov(:,1)) - min(fov(:,1))) / metadata.ImageWidth, ...
    (max(fov(:,2)) - min(fov(:,2))) / metadata.ImageLength ...
    ];
meta.zplanes2stack.derived.slicesSaved = nZslices;
meta.zplanes2stack.derived.cropEdgePixels = cropEdgePixels;
meta.zplanes2stack.derived.pixelSizeUm = pixelSizeUm;
meta.zplanes2stack.derived.bidiShiftPixels = bidishiftpixels;

%% Build the per-slice table
% zUm: the z position of each slice.
% ScanImage's header lists the z position of every frame acquired in
% SI.hStackManager.zs, relative to the start of the stack. The stage
% doesn't move during a slice, so we take each slice's first frame
% (e.g., frames  1, 101, 201, ... for a stack with 100 frames per slice). 
% These are indexed with the header's framesPerSlice, the number of
% frames *acquired*, which is more than the number saved when ScanImage
% averages frames (logAverageFactor > 1). If the line is missing
% (e.g. another ScanImage version), or holds fewer values than expected
% (which *might* be the case if it counts frames *saved* rather than
% *acquired* when frames are averaged with logAverageFactor > 1?...),
% say so and leave zUm as NaN rather than stopping.
zUm = nan(nZslices, 1);
zsLine = splitlines(siHeader);
zsLine = zsLine(startsWith(zsLine, 'SI.hStackManager.zs = '));
firstFrames = (0:nZslices-1)' * metadata.framesPerSlice + 1;
if isempty(zsLine)
    fprintf('SI.hStackManager.zs is not in the ScanImage header, so the slice table''s zUm is NaN.\n')
else
    [~, zs] = parseHeaderLine(zsLine{1});
    if numel(zs) >= firstFrames(end)
        zUm = reshape(zs(firstFrames), [], 1); % zs is a row; table columns are columns
    else
        fprintf(['SI.hStackManager.zs has %d values, too few for %d slices of %d frames, ' ...
            'so the slice table''s zUm is NaN.\n'], numel(zs), nZslices, metadata.framesPerSlice)
    end
end

% framesAtZeroShiftWithinSlice: from the *within*-slice registration.
% reg_coeffs(:, ii) holds the shift found for each frame of slice ii when it
% was registered to that slice's reference; OffsetPixel is [row column], in
% whole pixels. Count the frames with both equal to zero. A high count *may*
% indicate a poor registration (low signal-to-noise ratio; registration stuck
% at 0), but is also expected when the sample barely moved (less than half a
% pixel). Poor registrations were most often observed with sigma = 0.
% The count alone can't tell the two cases apart: compare results using a
% different sigma if there is any doubt.
% Exact zeros are meaningful when shifts are whole pixels: if we implement
% sub-pixel registration in the future, this will need to be swapped for a
% tolerance instead.
framesAtZeroShiftWithinSlice = zeros(nZslices, 1);
for ii = 1:nZslices
    offsets = vertcat(reg_coeffs(:, ii).OffsetPixel); % one [row column] per frame
    framesAtZeroShiftWithinSlice(ii) = sum(all(offsets == 0, 2));
end

% The shift and step columns are from the *between*-slice registration above
steps = [0 0; diff(shifts, 1, 1)];
slices = table((1:nZslices)', zUm, shifts(:,1), shifts(:,2), steps(:,1), steps(:,2), framesAtZeroShiftWithinSlice, ...
    'VariableNames', {'slice', 'zUm', 'shiftXPx', 'shiftYPx', 'stepXPx', 'stepYPx', 'framesAtZeroShiftWithinSlice'});

out = outStack;
channels = savedChannelID;

end % zplanes2stack


function [name, value] = parseHeaderLine(line)
% Split a ScanImage header line, "name = value", into its name and value.
%
% ScanImage writes each value as MATLAB syntax (e.g. 2, true, [0 2 4] or
% 'motor'), so evaluating the text gives the value with its proper type: a
% number, logical, array or char. read_SI_TIFF_header converts values the
% same way. This runs text from the TIFF file as MATLAB code, so it should
% only be used on files written by ScanImage.
name = extractBefore(line, ' = ');
value = eval(extractAfter(line, ' = '));

end % parseHeaderLine
