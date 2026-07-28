function im_filtered = suppressLowFreq(im, freq_cutoff)
    % High-pass filter an image stack to suppress low-frequency periodic noise
    %
    % function im_filtered = zstack.filtering.suppressLowFreq(im, freq_cutoff)
    %
    % Purpose
    % Slow intensity gradients and low-frequency periodic noise degrade image
    % registration. This function applies a Gaussian high-pass filter in the
    % frequency domain to each frame in turn.
    %
    % Inputs
    % im - 2D image or image stack (frames along the third dimension).
    % freq_cutoff - frequency threshold in cycles per image. Default 0.015
    %               e.g. freq_cutoff = 0.01 suppresses patterns slower than ~100 pixels.
    %
    % Outputs
    % im_filtered - the filtered image or image stack.
    %
    %
    % Rob Campbell - SWC 2026


    if nargin<2
        freq_cutoff = 0.015;
    end


    im = double(im);
    im_filtered = zeros(size(im),class(im));

    for ii=1:size(im,3)
       im_filtered(:,:,ii) = run_filter(im(:,:,ii),freq_cutoff);
   end

end % suppressLowFreq



function im_filtered = run_filter(im,freq_cutoff)
    % Apply the high-pass filter to a single frame

    F = fftshift(fft2(im));

    [height, width] = size(im);
    [X, Y] = meshgrid(-width/2:width/2-1, -height/2:height/2-1);
    freq_dist = sqrt(X.^2 + Y.^2) / max(height, width);  % normalize

    % High-pass: let high frequencies through, suppress low
    H = 1 - exp(-(freq_dist / freq_cutoff).^2);

    F_filtered = F .* H;
    im_filtered = real(ifft2(ifftshift(F_filtered)));

end % run_filter
