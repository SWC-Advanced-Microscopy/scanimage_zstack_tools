function [registered_stack,reg_params] = register_plane(orig_stack, refine, sigma)
    % Conduct the registration on one plane
    %
    % function [registered_stack,reg_params] = zstack.registration.register_plane(orig_stack, refine, sigma)
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
    % sigma - [optional] standard deviation of Gaussian filter to apply to the frames
    %         during registration. Default: 0 (no filtering).
    %
    % Outputs
    % registered_stack - the registered frames.
    % reg_params - the registration coefficients and related data.
    %
    %
    % Rob Campbell - SWC 2026

    % Our registration steps involve:
    %
    % - (optionally) blurring the frames to reduce noise
    % - averaging the most highly correlated frames to use as an initial target for registration
    % - calculating and applying the registration shifts to the blurred frames
    % - (optionally) refining the registration using the mean of the registered frames as a new target
    % - applying the final registration shifts to the original frames
    %
    % We have found that each of these steps can help reduce the impact of noise, artifacts, and
    % outlier frames. I.e., the registration is less likely to get "stuck" at 0 (as observed with
    % some noisy data) or jump erratically.

    if nargin < 2 || isempty(refine)
        refine = false;
    end

    if nargin < 3 || isempty(sigma)
        sigma = 0;
    end

    if sigma > 0
        stack = imgaussfilt(double(orig_stack), sigma);
    else
        stack = double(orig_stack);
    end

    orig_mu = zstack.registration.averageCorrelatedFrames(stack);
    [unrefined_stack,reg_params] = zstack.registration.apply_ffttrans(stack,orig_mu);

    if refine
        % Refine the registration using the mean of the registered frames
        refined_mu = mean(unrefined_stack, 3);
        [~,reg_params] = zstack.registration.apply_ffttrans(stack,refined_mu);
    end

    % Apply the shifts to the original frames.
    % NB. If we didn't blur or refine, registered_stack will be the same as unrefined_stack.
    %     (Re)apply the shifts to the original frames unconditionally anyway - it's cheap.
    registered_stack = zstack.registration.apply_ffttrans(orig_stack,reg_params.coef);

end % register_plane
