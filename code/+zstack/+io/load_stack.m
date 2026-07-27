function t_stack = load_stack(fname,chan)
% Loads the stack, returning one cell per z depth from a given channel.
%
% function t_stack = zstack.io.load_stack(fname,chan)


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

