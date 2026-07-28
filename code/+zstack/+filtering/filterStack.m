function t_stack = filterStack(t_stack, freq_cutoff)
    % Apply the high-pass filter to every depth of a loaded stack
    %
    % function t_stack = zstack.filtering.filterStack(t_stack, freq_cutoff)
    %
    % Purpose
    % Runs zstack.filtering.suppressLowFreq over each z depth of a stack loaded by
    % zstack.io.load_stack. This is the single point at which filtering is applied,
    % so that every channel is filtered identically before registration. If no
    % cutoff is supplied the stack is returned untouched, which allows the caller
    % to apply this unconditionally.
    %
    % Inputs
    % t_stack - cell array with one cell per z depth, as returned by
    %           zstack.io.load_stack.
    % freq_cutoff - frequency threshold in cycles per image. If zero, empty, or
    %               absent, no filtering is done.
    %
    % Outputs
    % t_stack - the filtered stack, with the same shape as the input.
    %
    %
    % Rob Campbell - SWC 2026


    if nargin<2 || isempty(freq_cutoff) || freq_cutoff<=0
        return
    end

    t_stack = cellfun(@(x) zstack.filtering.suppressLowFreq(x,freq_cutoff), ...
                      t_stack, 'uni', false);

end % filterStack
