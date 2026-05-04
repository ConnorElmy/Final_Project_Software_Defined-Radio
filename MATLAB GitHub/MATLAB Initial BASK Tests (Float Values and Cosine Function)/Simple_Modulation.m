%% Parameters
Fc = 2200;             % Carrier frequency
mHigh = 1.0;           % Modulation value for bit = 1
mLow = 0.2;            % Modulation value for bit = 0
Fs = 44100;            % Sample rate
bitDuration = 0.5;     % Seconds per bit
samplesPerBit = round(Fs * bitDuration);

%% Convert text to binary
text = 'Mr Watson, come here - I want to see you.';
textBinary = dec2bin(text);   % gives N characters × 8 bits per character
[numChars, numBits] = size(textBinary);

%% Generate audio for each bit
fullSignal = [];

for i = 1:numChars %Nested for to go through each bit of each character.
    for j = 1:numBits
        bitVal = textBinary(i,j);

        % Time base for this bit
        t = (0:samplesPerBit-1) / Fs;
        carrier = cos(2*pi*Fc*t);

        % Applies the correct modulation depth
        if bitVal == '1'
            amSignal = mHigh * carrier;
        else
            amSignal = mLow * carrier;
        end

        % Append to full audio waveform
        fullSignal = [fullSignal amSignal];
    end
end

%% Save final audio
filename = sprintf('AM_text_Fc%d_mHigh%.1f_mLow%.1f_Fs%d.wav', Fc, mHigh, mLow, Fs);

audiowrite(filename, fullSignal, Fs);

fprintf("File written: %s\n", filename);