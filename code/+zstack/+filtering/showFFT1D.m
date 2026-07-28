function showFFT1D(signal, title_str)
    % Display the 1D FFT magnitude spectrum with a frequency axis in cycles per pixel
    %
    % function zstack.filtering.showFFT1D(signal, title_str)
    %
    % Purpose
    % Plot the one-sided magnitude spectrum of a vectorised image (or any 1D signal)
    % so that periodic noise along the fast axis can be identified. The signal is
    % median filtered before the transform to suppress shot noise.
    %
    % Inputs
    % signal - 1D vector. e.g. frm(:) from a single frame.
    % title_str - optional title. Default: '1D FFT'
    %
    % Outputs
    % none
    %
    %
    % Rob Campbell - SWC 2026


    if nargin < 2
        title_str = '1D FFT';
    end


    signal = signal(:);  % ensure column vector
    signal = movmedian(signal, 10, 'Endpoints', 'shrink');
    N = length(signal);

    % 1D FFT
    F = fft(signal);
    mag = abs(F(1:floor(N/2)+1));  % one-sided spectrum (DC to Nyquist)

    % Frequency axis: cycles per sample
    freq = (0:floor(N/2)) / N;

    % Wavelength axis (inverse): pixels per cycle
    wavelength = 1 ./ (freq + eps);  % eps to avoid division by zero at DC

    % Drop DC, which otherwise dominates the plots and has infinite wavelength
    freq = freq(2:end);
    wavelength = wavelength(2:end);
    mag = mag(2:end);


    clf

    % Left: frequency domain (cycles per pixel)
    subplot(1, 2, 1);
    semilogy(freq, mag, 'LineWidth', 1.5);
    grid on
    xlim([0, freq(end)])
    xlabel('Frequency (cycles per pixel)');
    ylabel('Magnitude');
    title(title_str);


    % Right: same data against wavelength, which is easier to relate to the image
    subplot(1, 2, 2);
    loglog(wavelength, mag, 'LineWidth', 1.5);
    grid on
    set(gca, 'XDir', 'reverse') % So frequency still increases to the right
    xlim([wavelength(end), wavelength(1)])
    xlabel('Wavelength (pixels per cycle)');
    ylabel('Magnitude');
    title('Wavelength domain');

end % showFFT1D
