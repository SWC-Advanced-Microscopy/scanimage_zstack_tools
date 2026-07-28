function [registered_stack,reg_params] = register_plane(orig_stack,freq_cutoff)
    % Conduct the registration on one plane
    %
    % function [registered_stack,reg_params] = zstack.registration.register_plane(orig_stack,freq_cutoff)
    %
    % Purpose
    % Register all frames from one plane to the mean of that plane.
    %
    % Inputs
    % orig_stack - all frames from one plane.
    % freq_cutoff - [optional] if zero or empty no filtering is done. Otherwise a
    %               high-pass filter is applied. Default 0.015, which filters very
    %               low frequencies. This will need tweaking in future, as it is
    %               here only to handle existing noisy data.
    %
    % Outputs
    % registered_stack - the registered frames.
    % reg_params - the registration coefficients and related data.
    %
    %
    % Rob Campbell - SWC 2026


    if nargin<2
        freq_cutoff = 0.015;
    end

    if isempty(freq_cutoff)
        freq_cutoff=0;
    end

    if freq_cutoff>0
        orig_stack = zstack.filtering.suppressLowFreq(orig_stack, freq_cutoff);
    end

    orig_mu = mean(orig_stack,3);


    % Do the registration
    [registered_stack,reg_params] = zstack.registration.apply_ffttrans(orig_stack,orig_mu);

end % register_plane
