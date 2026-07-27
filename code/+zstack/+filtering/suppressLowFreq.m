function im_filtered = suppressLowFreq(im, freq_cutoff)
    % High-pass filter to suppress low-frequency periodic noise
    %
    % im_filtered = ztack.filtering.suppressLowFreq(im, freq_cutoff)
    %
    % Inputs:
    %   im           - 2D image
    %   freq_cutoff  - frequency threshold (in cycles per image)
    %                  e.g., freq_cutoff = 0.01 suppresses patterns slower than ~100 pixels

    if nargin<2
        freq_cutoff = 0.015;
    end

    im = double(im);
    im_filtered = zeros(size(im),class(im));

    for ii=1:size(im,3)
       im_filtered(:,:,ii) = run_filter(im(:,:,ii),freq_cutoff);
   end

end


function im_filtered = run_filter(im,freq_cutoff)
    F = fftshift(fft2(im));

    [height, width] = size(im);
    [X, Y] = meshgrid(-width/2:width/2-1, -height/2:height/2-1);
    freq_dist = sqrt(X.^2 + Y.^2) / max(height, width);  % normalize

    % High-pass: let high frequencies through, suppress low
    H = 1 - exp(-(freq_dist / freq_cutoff).^2);

    F_filtered = F .* H;
    im_filtered = real(ifft2(ifftshift(F_filtered)));
end
