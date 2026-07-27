function [output_stack,reg_params] = register_stack(input_stack)
% Loads the stack, returning one cell per z depth from a given channel.
%
%



for ii=1:length(input_stack)
    [output_stack{ii},reg_params{ii}] = zstack.registration.register_plane(input_stack{ii});
end


