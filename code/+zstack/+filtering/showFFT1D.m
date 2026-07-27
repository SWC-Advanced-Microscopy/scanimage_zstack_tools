function showFFT1D(signal, title_str)
    % Display 1D FFT magnitude spectrum with frequency axis in cycles per pixel
    %
    % Input:
    %   signal    - 1D vector (e.g., frm(:) from your frame)
    %   title_str - optional title

    if nargin < 2
        title_str = '1D FFT';
    end

    signal = signal(:);  % ensure column vector
    signal = movmedian(signal, 10, 'Endpoints', 'shrink');
    N = length(signal);

    % 1D FFT
    F = fft(signal);
    mag = abs(F(1:N/2+1));  % one-sided spectrum (DC to Nyquist)

    % Frequency axis: cycles per sample
    freq = (0:N/2) / N;

    % Wavelength axis (inverse): pixels per cycle
    wavelength = 1 ./ (freq + eps);  % eps to avoid division by zero at DC

    clf
    % Left: frequency domain (cycles per pixel)
    subplot(1, 2, 1);
    semilogy(freq, mag, 'LineWidth', 1.5);
