function im_filtered = notchFilterFFT(im, fx_target, fy_target, notch_width)
    % Notch filter at specific frequencies
    %
    % Inputs:
    %   im           - 2D image
    %   fx_target    - target x frequency (cycles per image), e.g. 0.08
    %   fy_target    - target y frequency (cycles per image), e.g. 0.02
    %   notch_width  - width of notch (try 0.005-0.02)
    %
    % Output:
    %   im_filtered - filtered image

    im = double(im);
    [height, width] = size(im);

    % 2D FFT
    F = fftshift(fft2(im));

    % Frequency grids (cycles per image)
    fx = (-width/2:width/2-1) / width;
    fy = (-height/2:height/2-1) / height;
    [FX, FY] = meshgrid(fx, fy);

    % Distance from target frequency in all quadrants
    % Account for 4-fold symmetry: peak appears at ±fx, ±fy
    dist = sqrt( (abs(FX) - abs(fx_target)).^2 + (abs(FY) - abs(fy_target)).^2 );

    % Gaussian notch: suppress frequencies close to target
    H = 1 - exp(-dist.^2 / (2 * notch_width^2));

    % Apply filter
    F_filtered = F .* H;

    % Inverse FFT
    im_filtered = real(ifft2(ifftshift(F_filtered)));
end
