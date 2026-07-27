function im_filtered = removePeriodicNoise(im, wavelength,fwidth)
    % Remove low-frequency periodic noise via notch filtering in frequency domain
    %
    % Inputs:
    %   im        - 2D image (single frame)
    %   wavelength - approximate wavelength of the periodic pattern in pixels
    %               (e.g., 512/4 = 128 pixels for 4 cycles per frame)
    %
    % Output:
    %   im_filtered - filtered image

    % Convert to double if needed
    im = double(im);

    % FFT
    F = fftshift(fft2(im));

    % Create notch filter centered on DC (+ other harmonics if needed)
    [height, width] = size(im);
    [X, Y] = meshgrid(-width/2:width/2-1, -height/2:height/2-1);

    % Frequency coordinates (in cycles per image)
    freq_dist = sqrt(X.^2 + Y.^2);

    % Notch: suppress frequencies corresponding to the periodic pattern
    % wavelength in pixels → frequency = 1/wavelength in cycles per pixel
    target_freq = 1 / wavelength;
    notch_width = fwidth;  % adjust based on how sharp you want the filter

    H = 1 - exp(-(freq_dist - target_freq).^2 / (2 * notch_width^2));

    % Apply filter
    F_filtered = F .* H;

    % Inverse FFT
    im_filtered = real(ifft2(ifftshift(F_filtered)));
end
