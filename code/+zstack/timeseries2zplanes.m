function out = timeseries2zplanes(fname,chan,freq_cutoff)
    % Build a z-stack from a multi-plane time series
    %
    % function out = zstack.timeseries2zplanes(fname,chan,freq_cutoff)
    %
    % Purpose
    % Feed in a time series, register the named channel, and return the registered
    % mean frames. The registration coefficients obtained from the named channel are
    % then applied to the remaining channels, so all channels stay in register with
    % one another.
    %
    % Every channel is high-pass filtered as it is loaded, before anything else
    % touches it. Filtering here rather than within the registration keeps all
    % channels treated identically.
    %
    % Inputs
    % fname - relative or absolute path to a ScanImage TIFF stack on disk.
    % chan - the channel used to calculate the registration.
    % freq_cutoff - [optional] frequency threshold in cycles per image for the
    %               high-pass filter applied to each channel. If zero or empty no
    %               filtering is done. Default 0.015, which filters very low
    %               frequencies. This will need tweaking in future, as it is here
    %               only to handle existing noisy data.
    %
    % Outputs
    % out - structure array with one element per saved channel and the fields:
    %       mean_z - the mean image at each z depth (x by y by depth).
    %       channel - the channel these data came from.
    %
    % Example
    % OUT = zstack.timeseries2zplanes('myTimeSeries.tif',1);
    %
    %
    % Rob Campbell - SWC 2026


    if nargin<3
        freq_cutoff = 0.015;
    end

    out = [] ; % in case of an error

    if isempty(fname) || ~exist(fname,'file')
        return
    end

    metadata = zstack.io.read_SI_TIFF_header(fname);

    savedChannelID = metadata.channelSave; % The indexes of the saved channels
    nZslices=metadata.numSlices; % number of z-stack slices.

    % Confirm we can return the desired depth and channel
    if ~any(savedChannelID==chan)
        fprintf('Channel %d does not exist in this stack\n', chan)
        return
    end


    % Load stack and register
    fprintf('Loading registration channel %d\n', chan)
    orig=zstack.io.load_stack(fname,chan);
    orig=zstack.filtering.filterStack(orig,freq_cutoff);

    fprintf('Running registration\n')
    [orig_reg, reg_coefs] = zstack.registration.register_stack(orig);


    % Generate the average images for this stack
    tmp = ones([size(orig_reg{1},1), size(orig_reg{1},2), nZslices], class(orig_reg{1}));

    for ii=1:length(orig_reg)
        tmp(:,:,ii) = mean(orig_reg{ii},3);
    end

    out.mean_z = tmp;
    out.channel = chan;


    % if only one channel we are done
    if length(savedChannelID)==1
        return
    end


    % Apply this to the other channels
    n=2;

    for c=1:length(savedChannelID)
        t_chan = savedChannelID(c);

        if t_chan == chan
            continue
        end

        fprintf('Loading channel %d\n', t_chan)
        t_stack=zstack.io.load_stack(fname,t_chan);
        t_stack=zstack.filtering.filterStack(t_stack,freq_cutoff);

        % Apply the registration
        tmp(:)=0;

        fprintf('Registering channel %d\n', t_chan)
        for ii=1:length(reg_coefs)
            t_reg = zstack.registration.apply_ffttrans(t_stack{ii},reg_coefs{ii}.coef);
            tmp(:,:,ii) = mean(t_reg,3);
        end

        out(n).mean_z = tmp;
        out(n).channel = t_chan;
        n=n+1;
    end

end % timeseries2zplanes
