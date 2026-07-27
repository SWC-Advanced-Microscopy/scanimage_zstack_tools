function im_filtered = notchFilter1D(im, freq_low, freq_high)
    % Notch filter 1D along vectorized frame
    % Transpose → vectorize → filter → reshape → transpose back
    %
    % Inputs:
    %   im        - 2D image frame
    %   freq_low  - lower frequency cutoff (default 0.02)
    %   freq_high - upper frequency cutoff (default 0.04)

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
end
