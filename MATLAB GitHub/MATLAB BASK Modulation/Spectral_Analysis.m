%% Read the audio file
% The filename suggests a 16-element LUT with a carrier frequency (Fc) of 2200Hz
%[wav1, fs1] = audioread("new_Integer_sin_array64_AM_Fc2200_mHigh1.0_mLow0.2_Fs140800.wav");
%[wav1, fs1] = audioread("new_Integer_sin_array4_AM_Fc2200_mHigh1.0_mLow0.2_Fs140800.wav");
%[wav1, fs1] = audioread("Integer_sin_array4_Fc2200_Fs140800.wav");
[wav1, fs1] = audioread("BASK_Integer_sin_array4_AM_Fc2200_mHigh1.0_mLow0.2_Fs140800.wav");

%% Convert stereo audio into mono.
if size(wav1,2) > 1, wav1 = mean(wav1,2); end
N1 = length(wav1);

%% FFT Calculation
W1 = fft(wav1);
f1 = (0:N1/2-1)*(fs1/N1);
f_kHz = f1/1000;

%% Convert to Magnitude then Decibels
mag1 = abs(W1(1:N1/2))./N1;
mag1_db = 20*log10(mag1 / max(mag1));

%% Professional Plot
figure('Color', 'w', 'Name', 'LUT Spectral Analysis');
plot(f_kHz, mag1_db, 'Color', [0 0.4470 0.7410], 'LineWidth', 1);

% --- Formatting ---
grid on; grid minor; box on;
set(gca, 'FontSize', 11, 'FontName', 'Helvetica');
xlim([0 fs1/10000]); %To around 14 kHz, which is roughly audio frequency
%ylim([-80 5]);    % Shows 80dB of dynamic range (standard for 8-10 bit systems)
ylim([-400 5]);    

% Labels
%No need for title, it will be included in the report
xlabel('Frequency (kHz)', 'FontSize', 12);
ylabel('Magnitude (dBc)', 'FontSize', 12); % dBc means dB relative to carrier
