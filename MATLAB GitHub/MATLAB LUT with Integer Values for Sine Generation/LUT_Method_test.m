% Example fixes for LUT_Method (concise)
Fc = 2200;
lutTable = sinewave_array_64_int;        % use actual table variable
elementsInLUT = numel(lutTable);
lutSize = 4;                            % effective LUT size to emulate (if desired)
% If you want fixed Fs independent of lutSize, set explicitly:
Fs = 140800;                            % desired sample rate

switch lutSize
    case 64, Increment = 1;
    case 32, Increment = 2;
    case 16, Increment = 4;
    case 8,  Increment = 8;
    case 4,  Increment = 16;
    otherwise, error('Incorrect LUT size.');
end

totalSamples = Fs*10;
fullSignal = zeros(1,totalSamples);
lutIndex = 1;
sampleCounter = 1;

for n = 1:totalSamples
    carrierSample = double(lutTable(lutIndex)) / 2047;
    fullSignal(n) = carrierSample;

    if sampleCounter < Increment
        sampleCounter = sampleCounter + 1;
    else
        % modulo wrap (keeps proper phase progression)
        lutIndex = mod(lutIndex - 1 + Increment, elementsInLUT) + 1;
        sampleCounter = 1;
    end
end

% Prefer writing double in [-1,1], or explicitly int16 if needed:
audiowrite(filename, fullSignal, Fs, 'BitsPerSample', 16);