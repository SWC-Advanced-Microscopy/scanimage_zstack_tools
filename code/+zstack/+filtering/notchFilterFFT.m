function im_filtered = notchFilterFFT(im, fx_target, fy_target, notch_width)
    % Notch filter an image at a specific 2D spatial frequency
    %
    % function im_filtered = zstack.filtering.notchFilterFFT(im, fx_target, fy_target, notch_width)
    %
    % Purpose
    % Suppress a single periodic component of an image by applying a Gaussian notch
    % centred on a known spatial frequency in the 2D FFT. The notch is applied in all
    % four quadrants, since a real image has a 4-fold symmetric spectrum.
    %
    % Inputs
    % im - 2D image.
    % fx_target - target x frequency in cycles per image. e.g. 0.08
    % fy_target - target y frequency in cycles per image. e.g. 0.02
    % notch_width - width of the notch. Try 0.005 to 0.02
    %
    % Outputs
    % im_filtered - the filtered image.
    %
    %
    % Rob Campbell - SWC 2026


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

end % notchFilterFFT
