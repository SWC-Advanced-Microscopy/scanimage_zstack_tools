function [out, channels, header] = zplanes2tiff(fname, chan, outFiles, varargin)
% Build a fully-registered z-stack and save one TIFF per channel.
%
% function [out, channels, header] = zstack.zplanes2tiff(fname, chan, outFiles, Name=Value)
%
% Purpose
% Runs zstack.zplanes2stack, then saves each channel of the result as a
% signed 16-bit TIFF with zstack.io.writeSignedTiff. The header returned by
% zplanes2stack goes into the Software tag of every file, followed by a
% zplanes2stack.derived.channel line giving the channel that file holds.
%
% The output file names are checked before registration starts, so a
% mistake there doesn't waste a long run.
%
% Inputs
% fname - relative or absolute path to a ScanImage TIFF stack on disk.
% chan - the channel used to calculate the registration.
% outFiles - cell array of output file names, one per saved channel, in the
%            order ScanImage saved them (its channelSave setting). Files
%            must not already exist.
%
% Optional name-value arguments
% Passed on to zstack.zplanes2stack; see its help.
%
% Outputs
% out, channels, header - as returned by zstack.zplanes2stack.
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
header = '';

% Check the output files before the long registration step
metadata = zstack.io.read_SI_TIFF_header(fname);
nChannels = length(metadata.channelSave);
if length(outFiles) ~= nChannels
    fprintf('%d output files given, but the stack has %d saved channels\n', ...
        length(outFiles), nChannels)
    return
end

existing = outFiles(cellfun(@isfile, outFiles));
if ~isempty(existing)
    fprintf('Output file already exists: %s\n', existing{:})
    return
end

[out, channels, header] = zstack.zplanes2stack(fname, chan, varargin{:});
if isempty(out)
    return
end

% Save each channel, adding the channel number to its header
for k = 1:length(channels)
    fprintf('Saving channel %d to %s\n', channels(k), outFiles{k})
    zstack.io.writeSignedTiff(out(:,:,:,k), outFiles{k}, ...
        [header sprintf('zplanes2stack.derived.channel = %d\n', channels(k))])
end

end % zplanes2tiff
