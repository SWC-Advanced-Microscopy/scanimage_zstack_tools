function [registered_stack,reg_params] = register_plane(orig_stack,freq_cutoff)
% Conduct the registration on one plane
%
%
% function [registered_stack,reg_params] = zstack.registration.register_stack(orig_stack,freq_cutoff)
%
% Purpose
% Register plane to its mean
%
% Inputs
% orig_stack - all frames from one plane
% freq_cutoff [optional] - if zero or empty no filtering done. Otherwise do a high-pass filter
%   By default we set to 0.015, which will filter very low frequencies. This will need
%   tweaking in future, as it's a just in here now to handle existing noisy data.
%
%
% Rob Campbell - SWC 2026


if nargin<2
    freq_cutoff = 0.015;
end

if ~isempty(freq_cutoff)
    freq_cutoff=0;
end

if freq_cutoff>0
    orig_stack = ztack.filtering.suppressLowFreq(orig_stack, freq_cutoff)
end

orig_mu = mean(orig_stack,3);


% Do the registration
[registered_stack,reg_params] = zstack.registration.apply_ffttrans(orig_stack,orig_mu);


