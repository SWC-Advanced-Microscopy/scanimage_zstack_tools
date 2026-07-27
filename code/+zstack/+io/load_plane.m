function im_stack = load_plane(fname,chan,depth)
% Load all frames with the same channel and depth
%
% function im_stack = zstack.io.load_plane(fname,chan,depth)


if isempty(fname) || ~exist(fname,'file')
    return
end

metadata = zstack.io.read_SI_TIFF_header(fname);

savedChannelID = metadata.channelSave; % The indexes of the saved channels
nZslices=metadata.numSlices; % number of z-stack slices.


% Confirm we can return the desired depth and channel
if ~any(savedChannelID==chan)
    fprintf('Channel %d does not exist in this stack\n', chan)
    return
end


if depth>nZslices
    fprintf('Requested depth %d but only %d exist in this stack\n', depth, nZslices)
    return
end


% Get the number of frames
t_info = imfinfo(fname);
numFramesInFile = length(t_info);
% TODO FOR TESTING
maxFrames=inf;
if numFramesInFile>maxFrames;
    numFramesInFile=maxFrames;
end

[~,sis]=zstack.utils.getFrameIndices(numFramesInFile,length(savedChannelID),nZslices,chan,depth);


cropEdgePixels = 30; % Crop this many pixels from the edges.
nrows = t_info(1).Height;
ncols = t_info(1).Width;
im_stack = tiffreadVolume(fname, 'PixelRegion', ...
    {[cropEdgePixels nrows-cropEdgePixels], [cropEdgePixels ncols-cropEdgePixels], sis});

