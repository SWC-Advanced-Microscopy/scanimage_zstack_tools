function [registered_stack,reg_params] = register_plane(orig_stack)
    % Conduct the registration on one plane
    %
    % function [registered_stack,reg_params] = zstack.registration.register_plane(orig_stack)
    %
    % Purpose
    % Register all frames from one plane to the mean of that plane. Any filtering
    % is applied by zstack.filtering.filterStack before the data reach this
    % function, so that all channels are treated identically.
    %
    % Inputs
    % orig_stack - all frames from one plane.
    %
    % Outputs
    % registered_stack - the registered frames.
    % reg_params - the registration coefficients and related data.
    %
    %
    % Rob Campbell - SWC 2026


    orig_mu = mean(orig_stack,3);


    % Do the registration
    [registered_stack,reg_params] = zstack.registration.apply_ffttrans(orig_stack,orig_mu);

end % register_plane
