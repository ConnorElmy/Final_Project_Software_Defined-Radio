%% Desciption
%Prototype of the BASK Demodulator
%VHDL compatible design, integer arithmetic, power-of-2 windows, 16x UART
%oversampling.


%Clear previous variables, command window and figures
clear; 
clc; 
close all;

%% Parameters, matching modulator

Fc = 2200; %Carrier frequency Hz
mhigh = 1.0;
mLow = 0.2; %Amplitude multiplier for bit 0 
bitRate = 2; %2 Bits per second
oversampleRate = 16; %For the 16x UART
bitsPerChar = 8; %Standard for ascii


%% Load WAV file

filename = 'combined_audio_easy.wav';
[signal, Fs] = audioread(filename);
signal = double(signal(:,1)); %Only read in a mono signal

samplesPerBit = round(Fs/bitRate);

%% Bandpass filter (BPF)
% Will this be done in hardware or software in the actual system?
%Attenutates the frequencies outside of the carrier

BPF_Bandwidth = 1000;
%Frequencies of filter, normalised to Nyquist rate
f_low = (Fc - BPF_Bandwidth/2) / (Fs/2);
f_high = (Fc + BPF_Bandwidth/2) / (Fs/2);

%2nd order butterworth IIR bandpass filter
[b_BPF, a_BPF] = butter(2, [f_low, f_high], 'bandpass');
%a and b are the numerator and denominator of the filters transfer
%function
filteredSignal = filter(b_BPF, a_BPF, signal);

%% Signal rectification

%Beginning of the envelope detection

%Can also implement with if sample(N) < 0, output = -sample(N) else ....
%This is how it will be implemented in VHDL.

rectified = abs(filteredSignal);

%% Moving Average Low-Pass Filter

%window lasts 1 carrier period, 64 samples
window = Fs / Fc;
windowPow2 = 2^nextpow2(window);

%64 elements so shift right by 6 bits
shift_amount = log2(windowPow2);

%convolution with a rectangular window to give a moving average
kernel = ones(1, windowPow2)/ windowPow2;
envelope = conv(rectified, kernel, 'same');

%% UART Oversampling

%16 samples per bit

M = samplesPerBit / oversampleRate; %70400/16 = 4400

%Take every Mth sample
envelopeSample = envelope(1:M:end);

%% Threshold

%Normalise from 0 to 1 for MATLAB, won't be done in the VHDL code
envelopeNormalised = envelopeSample / max(envelopeSample + eps);

%Calculate threshold
%Mean amplitude of a sinusoidal wave over a full cycle:
%A * 2/pi.
%Bit '1' = 1 * 2/pi = 0.637
%Bit '0' = 0.2 * 2/pi = 0.127

%Midpoint ratio from 0 to 0.637
% ((0.637 + 0.127)/2) / 0.637 = 0.6

threshold = 0.60;

bitsRaw = envelopeNormalised > threshold; %Comparison gives 0 or 1

%% Bit recovery

%Each bit occupies 16 samples, each of these samples is compared to the
%threshold. If a majority are above the threshold the bit is '1' and vice
%versa.

numPeriods = floor(length(bitsRaw) / oversampleRate);
recoveredBits = zeros(1, numPeriods);

for i = 1:numPeriods
    windowSlice = bitsRaw((i-1) * oversampleRate+1 : i*oversampleRate);
    majoritySum = sum(windowSlice);
    recoveredBits(i) = (majoritySum > oversampleRate/2);
end

%% Decode bits

%Group bits in 8-bit groups then convert to ascii text.
%FPGA UART needs start and stop bits.

numChar = floor(length(recoveredBits)/bitsPerChar);
decodedChars = '';

for i=1 : numChar

    asciiByte = recoveredBits((i-1)*bitsPerChar+1 : i*bitsPerChar);
    character = bi2de(asciiByte, 'left-msb');
    
    decodedChars = [decodedChars char(character)];

end

fprintf('Decoded WAV message: "%s" \n', decodedChars);

%% Plots 

figure('Name','BASK Demodulator Pipeline'); 

totalTime = (0:length(signal)-1) / Fs; 
totalSamples = (0:length(envelopeSample)-1)*M / Fs; 

subplot(4,1,1); 
plot(totalTime, signal); 
title('Raw BASK Signal'); xlabel('Time (s)'); ylabel('Amplitude'); 
xlim([0 min(4, totalTime(end))]); % Show first 4s 

subplot(4,1,2); 
plot(totalTime, envelope); 
title('Envelope after rectification and filtering'); xlabel('Time (s)'); ylabel('Amplitude'); 
xlim([0 min(4, totalTime(end))]); 

subplot(4,1,3); 
plot(totalSamples, envelopeNormalised); yline(threshold, 'r--', sprintf('Threshold = %.2f', threshold)); 
title(sprintf('%dx Oversampled Signal', oversampleRate)); xlabel('Time (s)'); ylabel('Normalised Amplitude');
xlim([0 min(4, totalSamples(end))]); 

subplot(4,1,4); 
t_bits = (0:length(recoveredBits)-1) / bitRate; 
stairs(t_bits, recoveredBits); 
title('Recovered Bits'); xlabel('Time (s)'); ylabel('Bit Value'); 
ylim([-0.2 1.2]); xlim([0 min(8, t_bits(end))]); 

%% BPF Frequency Response
figure('Name','Bandpass Filter Response'); 
freqz(b_BPF, a_BPF, 4096, Fs); 
title(sprintf('BPF: centre %d Hz, BW %d Hz', Fc, BPF_Bandwidth));

%% Generate BPF coefficients for the VHDL code

Fs = 140800; Fc = 2200; BW = 1000;
[b_BPF, a_BPF] = butter(2, [(Fc-BW/2),(Fc+BW/2)]/(Fs/2), 'bandpass');
sos = tf2sos(b_BPF, a_BPF);
fprintf('B1_0=%d  B1_2=%d  A1_1=%d  A1_2=%d\n', ...
    round(sos(1,1)*32768), round(sos(1,3)*32768), ...
    round(sos(1,5)*32768), round(sos(1,6)*32768));
fprintf('B2_0=%d  B2_2=%d  A2_1=%d  A2_2=%d\n', ...
    round(sos(2,1)*32768), round(sos(2,3)*32768), ...
    round(sos(2,5)*32768), round(sos(2,6)*32768));