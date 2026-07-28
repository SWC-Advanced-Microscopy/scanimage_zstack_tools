function t_stack = load_stack(fname,chan)
    % Load a whole ScanImage TIFF, returning one cell per z depth from a given channel
    %
    % function t_stack = zstack.io.load_stack(fname,chan)
    %
    % Purpose
    % Loop over all z depths in the file and load the frames from the requested
    % channel at each depth. This is a convenience wrapper around
    % zstack.io.load_plane.
    %
    % Inputs
    % fname - relative or absolute path to a ScanImage TIFF stack on disk.
    % chan - the channel to load.
    %
    % Outputs
    % t_stack - cell array with one cell per z depth. Each cell contains all frames
    %           acquired at that depth. Empty if the requested channel does not exist.
    %
    %
    % Rob Campbell - SWC 2026


    t_stack = []; % in case of an error

    if isempty(fname) || ~exist(fname,'file')
        return
    end

    metadata = zstack.io.read_SI_TIFF_header(fname);

    savedChannelID = metadata.channelSave; % The indexes of the saved channels

    % Confirm we can return the desired depth and channel
    if ~any(savedChannelID==chan)
        fprintf('Channel %d does not exist in this stack\n', chan)
        return
    end


    nZslices=metadata.numSlices; % number of z-stack slices.

    for ii=1:nZslices
        t_stack{ii} = zstack.io.load_plane(fname,chan,ii);
    end

end % load_stack
