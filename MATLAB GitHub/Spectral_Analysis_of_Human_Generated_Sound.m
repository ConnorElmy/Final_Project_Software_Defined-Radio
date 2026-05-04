%% Read audio file
[wav1, fs1] = audioread("Kids Children Screaming - Schreiende Kinder - Ringtone Sound Effects - Free Download - Geschrei.wav");

%% Make the audio mono if stereo
if size(wav1,2) > 1, wav1 = mean(wav1,2); end

%% Calculate FFT and Frequencies
N1 = length(wav1);
X1 = fft(wav1);
f1 = (0:N1/2-1)*(fs1/N1);
f_kHz = f1/1000;

%% Convert to Magnitude and then to Decibels (dB)
% Normalising to the peak (0 dB)
mag1 = abs(X1(1:N1/2)) ./ N1;
mag1_db = 20 * log10(mag1 / max(mag1));

%% Plotting
figure('Color', 'w'); % White background for the report
plot(f_kHz, mag1_db, 'Color', [0.2 0.2 0.2], 'LineWidth', 0.8); %Grey Plot

grid on;
grid minor;
box on;
set(gca, 'FontSize', 30, 'FontName', 'Helvetica');
xlim([0 10]); % Focus on the human voice range (up to 10kHz)
ylim([-80 5]);   % Show 80dB of dynamic range

% Labels and Title
title("Spectral Analysis of Human-Generated Sound", 'FontSize', 40);
xlabel('Frequency (kHz)', 'FontSize', 30);
ylabel('Magnitude (dB)', 'FontSize', 30);