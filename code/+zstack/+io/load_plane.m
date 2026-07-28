function im_stack = load_plane(fname,chan,depth)
    % Load all frames from one channel at one depth of a ScanImage TIFF
    %
    % function im_stack = zstack.io.load_plane(fname,chan,depth)
    %
    % Purpose
    % A ScanImage time series interleaves channels and depths within a single TIFF.
    % This function pulls out every frame belonging to one channel/depth combination
    % and returns them as an image stack. The edges of each frame are cropped, as
    % these contain turnaround artifacts.
    %
    % Inputs
    % fname - relative or absolute path to a ScanImage TIFF stack on disk.
    % chan - the channel to load.
    % depth - the z depth (slice index) to load.
    %
    % Outputs
    % im_stack - all frames from the requested channel and depth. Empty if the
    %            requested channel or depth does not exist in the file.
    %
    %
    % Rob Campbell - SWC 2026


    im_stack = []; % In case of an error
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

    % The frames are interleaved by the position of the channel within the saved
    % channels, not by its ScanImage channel ID. e.g. if channels 2 and 3 were
    % saved, channel 3 occupies the second slot of each interleave cycle.
    chanIndex = find(savedChannelID==chan);

    if depth>nZslices
        fprintf('Requested depth %d but only %d exist in this stack\n', depth, nZslices)
        return
    end


    % Get the number of frames
    t_info = imfinfo(fname);
    numFramesInFile = length(t_info);

    % TODO FOR TESTING
    maxFrames=inf;
    if numFramesInFile>maxFrames
        numFramesInFile=maxFrames;
    end

    [~,sis]=zstack.utils.getFrameIndices(numFramesInFile,length(savedChannelID),nZslices,chanIndex,depth);


    nrows = t_info(1).Height;
    ncols = t_info(1).Width;

    cropEdgePixels = round(ncols*0.058); % Crop this many pixels from the edges.
    im_stack = tiffreadVolume(fname, 'PixelRegion', ...
        {[1, nrows], [cropEdgePixels+1, ncols-cropEdgePixels], sis});

end % load_plane
