%% Desciption
%BASK using a LUT representation for the sinewave carrier.
%Testing done with a 64-element array which is counted through at different
%rates to simulate different LUT lengths.

%Removed phase incrementation, as we count in multiples of powers of 2 the
%array will always start and exit at the last value of the LUT. Simplifes
%the code.

%Wrap around at 63 has to be done manually, in the VHDL code this would be
%automatic as a 6-bit number could be used as the counter.
%% Parameters

Fc = 2200; %Carrier frequency
elementsInLUT = 64; %Keep this constant

lutSize = 4;

Fs = Fc * 64; %Sample frequency, determined by how many samples need to be performed a second.
%140800 for 2200 Hz, 64-element case.
%The sample frequency required for the 4 element case would be 2200*4 =
%8800Hz, which gives a Nyquist rate of 4400Hz. Since I want to be able to
%analyse the spectrums of each case up to 10kHz I will keep the sample
%frequency the same for each case to simplify this.


%% Timing values

totalSamples = Fs *10; %10 seconds of sound

fullSignal = zeros(1, totalSamples); %Preallocate the size of the signal as it was causing a lot of slowdown

%% Sinewave array

%Generated using Dr LUT - Free Lookup Table Generator
%https://github.com/ppelikan/drlut
%Formula: sin(2*pi*t/T)

sinewave_array_64_int = [0 201 399 594 783 965 1137 1299 1447 1582 1702 1805 1891 1959 2008 2037 2047 2037 2008 1959 1891 1805 1702 1582 1447 1299 1137 965 783 594 399 201 0 -201 -399 -594 -783 -965 -1137 -1299 -1447 -1582 -1702 -1805 -1891 -1959 -2008 -2037 -2047 -2037 -2008 -1959 -1891 -1805 -1702 -1582 -1447 -1299 -1137 -965 -783 -594 -399 -201];

%% Generate audio

%Sets different values for incrementation based on the LUT size is being
%emulated. Has to be a power of two to simplify the code, this allows the 
%array to start at the first element each time.

switch lutSize
    case 64
        Increment = 1;
    case 32
        Increment = 2;
    case 16
        Increment = 4;
    case 8
        Increment = 8;
    case 4 %4-element is the Nyquist limit for a 0.5s signal.
        Increment = 16;
    otherwise
        error('Incorrect LUT size.');
end

sampleFrequencyBuffer = 1;
lutIndex = 1;
writeArray = 1;

for i=1:1:totalSamples

            carrierSample = double(sinewave_array_64_int(lutIndex))/2047; 
            %Convert integer to a float so it can be saved to a WAV.

            out = carrierSample;

        fullSignal(writeArray) = out;
        writeArray = writeArray +1;

        if sampleFrequencyBuffer < Increment
            sampleFrequencyBuffer = sampleFrequencyBuffer + 1;
        else
            lutIndex = lutIndex + Increment; %Wait to increment based on the LUT length being simulated, the same sample value will be used next loop.
            sampleFrequencyBuffer = 1;
        end

        if lutIndex>elementsInLUT
            lutIndex = 1;
        end

        
end

%% Save final audio

filename = sprintf('Integer_sin_array%d_Fc%d_Fs%d.wav', lutSize, Fc, Fs);
audiowrite(filename, int16(fullSignal*32767), Fs, 'BitsPerSample',16);