function [out, channels] = zplanes2stack(fname,chan,freq_cutoff, refine, sigma)
% Build a fully-registered z-stack from a multi-plane series.
%
% function [out, channels] = zstack.zplanes2stack(fname,chan,freq_cutoff)
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
% Inputs
% fname - relative or absolute path to a ScanImage TIFF stack on disk.
% chan - the channel used to calculate the registration.
% freq_cutoff - [optional] frequency threshold in cycles per image for the
%               high-pass filter applied to each channel. If zero or empty no
%               filtering is done, which is the default. A value of about
%               0.015 filters very low frequencies. The filter is not enabled
%               by default because it needs more work.
% refine      - [optional] boolean flag to indicate whether to refine the 
%               registration using the mean of the registered frames.
%               Default: false.
% sigma      - [optional] standard deviation of Gaussian filter to apply to
%               the frames during registration. Default: 0 (no filtering).
% Outputs
% out - a 4D array (Y, X, Z, channel) containing the registered z-stack.
% channels - a 1D array containing the channel numbers corresponding to the
%            4th dimension of `out`.
%
% Examples
%
% - Register on channel 1 with no filtering
% >> OUT = zstack.zplanes2stack('myUnregisteredZstack.tif',1);
%
% - The same, but high-pass filter the data first
% >> OUT = zstack.zplanes2stack('myUnregisteredZstack.tif',1,0.015);


if nargin<3 || isempty(freq_cutoff)
    freq_cutoff = 0; % No filtering by default
end

if nargin < 4 || isempty(refine)
    refine = false; % No refinement by default
end

if nargin < 5 || isempty(sigma)
    sigma = 0; % No blurring by default
end

out = [] ; % in case of an error

% Preemptively promote fname to a cell array in case our stack is split
% across multiple files.
fname = {fname};

if isempty(fname{1}) || ~exist(fname{1},'file')
    fprintf('File %s does not exist\n', fname{1})
    return
end

%% Open TIFF and collect ScanImage metadata

t = Tiff(fname{1});
metadata = zstack.io.read_SI_TIFF_header(t);

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

    % Crop artefacts from image edges prior to performing the registration
    thisZslice = thisZslice(:, uncroppedCols,  :, :);

    % Apply filtering to all channels
    if freq_cutoff > 0
        for kk = 1:nChannels
            thisZslice(:, :, :, kk) = zstack.filtering.suppressLowFreq(thisZslice(:, :, :, kk), freq_cutoff);
        end
    end

    % Perform registration on chosen channel.
    % Store the registration parameters to be applied to the other channels.
    [registeredChannel, reg_params_out] = zstack.registration.register_plane( ...
        thisZslice(:, :, :, chan_idx), ...
        refine, ...
        sigma ...
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

for ii = 2:nZslices

    % Using the same registration channel, register each slice to the
    % previous one in sequence. Shifts accumulate down the stack.
    tform = imregcorr(outStack(:, :, ii, chan_idx), outStack(:, :, ii-1, chan_idx), 'translation');

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

out = outStack;
channels = savedChannelID;

end % zplanes2stack