function [output_stack,reg_params] = register_stack(input_stack)
    % Register every plane in a loaded stack
    %
    % function [output_stack,reg_params] = zstack.registration.register_stack(input_stack)
    %
    % Purpose
    % Loop over the z depths of a stack loaded by zstack.io.load_stack and register
    % each plane to its own mean image.
    %
    % Inputs
    % input_stack - cell array with one cell per z depth, as returned by
    %               zstack.io.load_stack.
    %
    % Outputs
    % output_stack - cell array of registered frames, one cell per z depth.
    % reg_params - cell array of registration coefficients, one cell per z depth.
    %
    %
    % Rob Campbell - SWC 2026


    for ii=1:length(input_stack)
        [output_stack{ii},reg_params{ii}] = zstack.registration.register_plane(input_stack{ii});
    end

end % register_stack
