%% Description
%This code performs BASK on a cosine and then quantises the values to
%simulate an N-bit DAC

%% Parameters

Fc = 2200;      %Carrier frequency
mHigh = 1.0;      % Modulation depths High means bit =1
mLow = 0.25;
Fs = 144100;     % Audio sample rate (Hz)
timePerSampleBit = 0.5;
samplesPerBit = round(Fs*timePerSampleBit);     
DAC_bit_val = 16;
%This bit val gives this many steps
steps = power(2,DAC_bit_val); 

%% Create text to send
text = 'Hi!';

textBinary = dec2bin(text, 8); %binary version

[numChars, numBits] = size(textBinary);


%% Generate audio
totalSamples = numChars * numBits * samplesPerBit;

fullSignal = zeros(1, totalSamples); %Preallocate the size of the signal as it was causing a lot of slowdown

%time array
t_total = (0:totalSamples-1)/Fs;
carrier_total = cos(2*pi*Fc*t_total);

%Set the sine to be unipolar like the DAC so 0 to 1
%carrier_total = (cos(2*pi*Fc*t_total)+1)/2;

bit_count = 0;
for i=1:1:numChars
    for j=1:1:numBits
        bit_count = bit_count + 1;
        arrayVal = textBinary(i,j);

        %position
        carrier_position = (bit_count -1) *samplesPerBit +1: bit_count*samplesPerBit;

        %Modulation
        if arrayVal=='1'
            fullSignal(carrier_position) = carrier_total(carrier_position)*mHigh;
        elseif arrayVal=='0'
            fullSignal(carrier_position) = carrier_total(carrier_position)*mLow;
        else
            disp('error');
        end
    end
end

%Quantisation error from DAC/ADC
idealSignal = fullSignal;

Vmax = max(idealSignal);
Vmin = min(idealSignal);
LSB = (Vmax - Vmin)/(steps-1); %Amplitude of minimum step size.

fullSignal = Vmin + LSB * round((idealSignal - Vmin)/ LSB); %Convert each sample to its nearest quantisation step.
%Converts the signal into the DAC staircase
%fullsignal/LSB recscales to the number of quantisation steps needed to
%represent a value, round brings it to the closest value, *LSB brings it
%back to a value which can be output to the WAV.
quantizedSignal = fullSignal;
errorSignal = idealSignal - fullSignal;

%output

%Ensure audio is -1 to 1
maxAbs = max(abs(fullSignal));
if maxAbs > 1
    fullSignal = fullSignal / maxAbs;
    quantizedSignal = quantizedSignal / maxAbs;
    errorSignal = errorSignal / maxAbs;
end

filename = sprintf('BASK_DAC_Bit_Value_%d.wav', DAC_bit_val);
audiowrite(filename, fullSignal, Fs);

filename = sprintf('BASK_error_myDAC_Bit_Value_%d.wav', DAC_bit_val);
audiowrite(filename, errorSignal, Fs);

%% Time-Domain Visualization (Zoomed in for clarity)
figure('Name', 'Time Domain Analysis'); 
t_zoom = 1:500; % Look at the first 500 samples (~11ms at 44.1kHz) 
subplot(2,1,1); 
plot(t_total(t_zoom), idealSignal(t_zoom), 'k', 'LineWidth', 2); hold on; 
stairs(t_total(t_zoom), quantizedSignal(t_zoom), 'r--', 'LineWidth', 1); 
title(['Ideal vs. Quantized Signal (', num2str(DAC_bit_val), '-bit)']); 
legend('Ideal (Actual)', 'Quantized'); 
ylabel('Amplitude'); grid on; 
subplot(2,1,2); plot(t_total(t_zoom), errorSignal(t_zoom), 'r'); 
title('Quantization Error (The "Noise")'); xlabel('Time (s)'); 
ylabel('Amplitude'); grid on; % Save both for analysis audiowrite(sprintf('Quantized_%dbit.wav', DAC_bit_val), quantizedSignal, Fs, 'BitsPerSample', 32);