function [indices,startIncrStop] = getFrameIndices(n, c, z, tC, tZ)
    % Get frame indices for a specific channel and z-depth
    %
    % zstack.utils.getFrameIndices(n, c, z, tC, tZ)
    %
    % Frames are interleaved as: [c1z1, c2z1, c1z2, c2z2, c1z3, c2z3, ...]
    % i.e., channel cycles fastest, then z-depth
    %
    % Inputs:
    %   n  - total number of frames
    %   c  - number of channels
    %   z  - number of z-depths
    %   tC - target channel (1 to c)
    %   tZ - target z-depth (1 to z)
    %
    % Output:
    %   indices - 1-D array of frame indices (1-indexed) for the requested c,z
    %   startIncrStop - [firstIndex, increment, lastIndex]

    % Validate inputs
    if nargin<5
        fprintf('%s requires 5 input arguments\n', mfilename)
        return
    end

    if tC < 1 || tC > c
        error('tC must be between 1 and %d', c);
    end
    if tZ < 1 || tZ > z
        error('tZ must be between 1 and %d', z);
    end

    % Frames per z-depth (all channels)
    frames_per_z = c;

    % Offset for target z-depth (0-indexed internally, then convert to 1-indexed)
    z_offset = (tZ - 1) * frames_per_z;

    % Offset within a z-depth for target channel (0-indexed)
    c_offset = tC - 1;

    % Generate all indices
    num_timepoints = n / (c * z);  % assumes n divides evenly
    timepoint_indices = 0:num_timepoints-1;

    indices = z_offset + c_offset + timepoint_indices * (c * z) + 1;  % +1 for 1-indexing

    % Ensure we don't exceed n
    indices = indices(indices <= n);

    startIncrStop = [indices(1), c*z, indices(end)];
end
