% Example fixes for Spectral_Analysis
[wav1, fs1] = audioread("Integer_sin_array4_Fc2200_Fs140800.wav");
if size(wav1,2) > 1, wav1 = mean(wav1,2); end
N = length(wav1);

% detrend and window
x = detrend(wav1);
w = hann(N);
X = fft(x .* w, N);

% single-sided length
Nhalf = floor(N/2) + 1;
f = (0:Nhalf-1)*(fs1/N) / 1000;   % kHz

% magnitude scaling: correct single-sided amplitude (account for window coherent gain)
coherentGain = sum(w)/N;
mag = abs(X(1:Nhalf)) * 2 / (N * coherentGain);
mag_db = 20*log10(mag / max(mag) + eps);    % dBc, avoids -Inf

figure('Color','w');
plot(f, mag_db, 'LineWidth', 1);
grid on; box on;
xlabel('Frequency (kHz)');
ylabel('Magnitude (dBc)');
xlim([0, fs1/2000]);   % in kHz: fs/2 -> fs1/2000 kHz
ylim([-120, 5]);