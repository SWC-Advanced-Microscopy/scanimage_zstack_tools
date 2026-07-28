function im_filtered = notchFilter1D(im, freq_low, freq_high)
    % Notch filter a frame along the vectorised fast axis
    %
    % function im_filtered = zstack.filtering.notchFilter1D(im, freq_low, freq_high)
    %
    % Purpose
    % Treats the image as a single 1D signal running along the fast (line) axis and
    % removes a band of frequencies from it. The frame is transposed, vectorised,
    % filtered, reshaped, and transposed back.
    %
    % Inputs
    % im - 2D image frame.
    % freq_low - lower frequency cutoff. Default 0.02
    % freq_high - upper frequency cutoff. Default 0.04
    %
    % Outputs
    % im_filtered - the filtered image.
    %
    %
    % Rob Campbell - SWC 2026


    if nargin < 2
        freq_low = 0.02;
    end

    if nargin < 3
        freq_high = 0.04;
    end


    [H, W] = size(im);
    im = im';
    signal = im(:);

    F = fft(signal);
    N = length(signal);
    freq = (0:N-1) / N;

    % Notch: suppress freq_low to freq_high (both positive and negative freqs)
    notch_mask = ((freq >= freq_low) & (freq <= freq_high)) | ((freq >= 1-freq_high) & (freq <= 1-freq_low));
    F(notch_mask) = 0;

    signal_filtered = real(ifft(F));
    im_filtered = reshape(signal_filtered, W, H)';

end % notchFilter1D
