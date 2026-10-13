function [registered_stack,reg_params] = register_plane(orig_stack, refine)
    % Conduct the registration on one plane
    %
    % function [registered_stack,reg_params] = zstack.registration.register_plane(orig_stack, refine)
    %
    % Purpose
    % Register all frames from one plane to a representative average of that plane.
    % Any filtering is applied by zstack.filtering.filterStack before the data reach
    % this function, so that all channels are treated identically.
    %
    % Inputs
    % orig_stack - all frames from one plane.
    % refine - [optional] boolean flag to indicate whether to refine the registration
    %          using the mean of the registered frames. Default: false.
    %
    % Outputs
    % registered_stack - the registered frames.
    % reg_params - the registration coefficients and related data.
    %
    %
    % Rob Campbell - SWC 2026

    if nargin < 2
        refine = false;
    end

    orig_mu = zstack.registration.averageCorrelatedFrames(orig_stack);

    % Do the registration
    [registered_stack,reg_params] = zstack.registration.apply_ffttrans(orig_stack,orig_mu);

    if refine
        % Refine the registration using the mean of the registered frames
        refined_mu = mean(registered_stack, 3);
        [registered_stack,reg_params] = zstack.registration.apply_ffttrans(orig_stack,refined_mu);
    end

end % register_plane
