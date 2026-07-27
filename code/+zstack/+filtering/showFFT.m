function showFFT(im)
    % Display FFT magnitude spectrum with frequency axes in cycles per image
    %
    % Input:
    %   im - 2D image (single frame)

    im = double(im);
    im = mean(im,3);
    [height, width] = size(im);

    % 2D FFT
    F = fftshift(fft2(im));
    mag = log10(abs(F) + 1);  % log scale to see both large and small peaks

    % Frequency axes (cycles per image)
    fx = (-width/2:width/2-1) / width;
    fy = (-height/2:height/2-1) / height;

    % Display
    clf
    % Left: FFT magnitude
    subplot(1, 2, 1);
    imagesc(fx, fy, mag);
    %axis image xy;
    colorbar;
    xlabel('Frequency (cycles per image width)');
    ylabel('Frequency (cycles per image height)');
    title('FFT Magnitude (log scale)');

    % Right: Zoom on low frequencies (first 10% of spectrum)
    subplot(1, 2, 2);
    low_freq_range = 0.1;
    fx_mask = abs(fx) < low_freq_range;
    fy_mask = abs(fy) < low_freq_range;
    mag_zoomed = mag(fy_mask, fx_mask);
    fx_zoom = fx(fx_mask);
    fy_zoom = fy(fy_mask);

    imagesc(fx_zoom, fy_zoom, mag_zoomed);
    axis image xy;
    colorbar;
    xlabel('Frequency (cycles per image width)');
    ylabel('Frequency (cycles per image height)');
    title('Low-frequency detail (zoomed)');
end
