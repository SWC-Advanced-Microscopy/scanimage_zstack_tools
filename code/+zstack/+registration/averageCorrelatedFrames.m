function avgFrame = averageCorrelatedFrames(frames, nCor)
% Construct an appropriate target frame for within-slice registration.
%
% function avgFrame = zstack.registration.averageCorrelatedFrames(frames, nCor)
%
% Purpose
% Given time series frames from a z-slice, find the frame whose nCor best
% matches have the highest average correlation. Average over these nCor + 1
% frames to return a target frame for within-slice registration.
%
% Inputs
% frames - all frames from one plane/slice
% nCor   - the number of frames to use when evaluating the most highly
%          correlated frame. Capped at the number of frames minus one
%          (optional; defaults to 20).
%
% Outputs
% avgFrame - a single averaged frame for the slice, suitable for use as a
%            target for within-slice registration.

if nargin < 2
    nCor = 20;
end

% Flatten height and width dims, reshaping (Y x X x t) matrix into a 2D (pixels x t)
[height, width, t] = size(frames);
flattenedFrames = reshape(frames, height * width, t);

% Compute 2D numFrames x numFrames correlation matrix between frames.
% Set diagonal (self-correlated; always 1) to -Inf to avoid ever selecting
% self-correlated frames as top correlated pairs.
R = corrcoef(double(flattenedFrames)); 
R(1:t+1:end) = -Inf;

% Cap nCor in case a slice has fewer than nCor + 1 frames.
% Without this, the -Inf diagonal gets erroneously picked up by the
% maxk call below and pollutes the subsequent logic.
nCor = min(nCor, t - 1);

% For each frame, find its nCor most correlated frames (excluding itself)
[topFrames, topIdxs] = maxk(R, nCor, 2);

% Find which single frame is most highly correlated with other frames and
% extract it and its partners
corrScores = mean(topFrames, 2);
[~, bestFrameIdx] = max(corrScores);
partnerIdxs = topIdxs(bestFrameIdx, :);

% Average the best frame and its partners
avgFrame = mean(frames(:, :, [bestFrameIdx, partnerIdxs]), 3);

end