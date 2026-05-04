%%Notes
%Should be 48dB between 8bit and 16 bit values
%signal to quantisation noise value is given by
%SQNR = 6.02N +1.76dB where N is the number of bits in the DAC.

%% Read audio file

[wav1, fs] = audioread("DAC_Bit_Value_4.wav");
%[wav1, fs] = audioread("DAC_Bit_Value_12.wav");
[wav2, ~] = audioread("DAC_Bit_Value_16.wav");

%[wav1, fs] = audioread("myDAC_Bit_Value_12.wav");

%% Make mono if stereo
if size(wav1,2) > 1, wav1 = mean(wav1,2); end
if size(wav2,2) > 1, wav2 = mean(wav2,2); end

%% Make same length
minLength = min(length(wav1), length(wav2));
wav1 = wav1(1:minLength);
wav2 = wav2(1:minLength);

%% Calculate Power Spectral Density (PSD) using Welch's Method
% Define parameters for Welch's method
windowLength = round(fs / 2);      % 100ms window gives good frequency resolution
window = hann(windowLength,"periodic");         % Hann window prevents spectral leakage
noverlap = round(windowLength / 2);  % 50% overlap is standard practice
nfft = 2^nextpow2(windowLength)*4;   % Zero-padding interpolates the spectrum for smoother curves

% Compute PSD (pxx will have units of Power/Hz)
[pxx8, f] = pwelch(wav1, window, noverlap, nfft, fs);
[pxx16, ~] = pwelch(wav2, window, noverlap, nfft, fs);

%% Convert to Decibels (dB/Hz)
% Add eps (a tiny number) to prevent taking the log of zero
pxx8_dB = 10*log10(pxx8 + eps);
pxx16_dB = 10*log10(pxx16 + eps);





% %% Plot Formatting for Academic Report
% 
% f_khz = f / 1000;
% 
% figure('Color', 'w');
% plot(f_khz, pxx8_dB, 'LineWidth', 1.0, 'Color', [0.85 0.325 0.098], 'DisplayName', '8-bit DAC'); 
% hold on;
% plot(f_khz, pxx16_dB, 'LineWidth', 1.0, 'Color', [0 0.447 0.741], 'DisplayName', '16-bit DAC'); 
% 
% grid on;
% 
% title('Comparison of 8-Bit and 16-bit DAC quantisation noise', 'FontSize', 14, 'FontWeight', 'bold');
% xlabel('Frequency (kHz)', 'FontSize', 12);
% ylabel('Power Spectral Density (dB/Hz)', 'FontSize', 12);
% 
% legend('Location','northeast');
% 
% % Frame the plot nicely to highlight the carrier and the noise floor
% xlim([0 5]);  
% ylim([-160 -20]);
% 
% %% Calculate and Display Theoretical vs Measured Difference 
% % We estimate noise floor by taking the median value (ignoring the carrier peak) 
% noiseFloor8 = median(pxx8_dB); 
% noiseFloor16 = median(pxx16_dB); 
% measuredDiff = noiseFloor8 - noiseFloor16; 
% fprintf('--- Results ---\n'); 
% fprintf('Measured Noise Floor Difference: %.2f dB\n', measuredDiff); 
% fprintf('Theoretical Difference (6.02 * 8 bits): 48.16 dB\n');
% 
% 



%% Carrier frequency bin exclusion
carrierFreq = 2200;                       % set to your carrier
exclBW = 200;                             % exclude ±exclBW Hz around carrier
excludeIdx = (f >= carrierFreq - exclBW) & (f <= carrierFreq + exclBW);

% Optionally exclude harmonics if present
harmonics = carrierFreq * (2:5);
for h = harmonics
    excludeIdx = excludeIdx | ((f >= h - exclBW) & (f <= h + exclBW));
end

% Define noise band of interest, e.g., 0.5 kHz to 5 kHz excluding carrier region
noiseBand = (f >= 500) & (f <= 5000) & ~excludeIdx;

% Noise floor estimate using median of PSD in noiseBand
noiseFloor8_dB  = median(pxx8_dB(noiseBand));
noiseFloor16_dB = median(pxx16_dB(noiseBand));
measuredDiff_dB = noiseFloor8_dB - noiseFloor16_dB;

% Alternatively compute integrated noise power in the band and convert to dB
noisePower8  = trapz(f(noiseBand), pxx8(noiseBand));
noisePower16 = trapz(f(noiseBand), pxx16(noiseBand));
noisePower8_dB  = 10*log10(noisePower8 + eps);
noisePower16_dB = 10*log10(noisePower16 + eps);
measuredDiffIntegrated_dB = noisePower8_dB - noisePower16_dB;

% Display results
fprintf('Median noise floor difference 8bit-16bit = %.2f dB\n', measuredDiff_dB);
fprintf('Integrated noise difference 8bit-16bit = %.2f dB\n', measuredDiffIntegrated_dB);
fprintf('Theoretical difference = %.2f dB\n', 6.02*(16-8));

% Plot
figure('Color','w');
plot(f/1000, pxx8_dB, 'r', 'LineWidth', 1); hold on;
plot(f/1000, pxx16_dB,'b', 'LineWidth', 1);
xlim([0 5]);
ylim([-160 -20]);
xlabel('Frequency kHz');
ylabel('PSD dB/Hz');
legend('8-bit','16-bit');
grid on;