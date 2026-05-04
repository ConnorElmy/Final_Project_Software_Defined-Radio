% Define the filenames
file1 = 'BASK_Quieter_looped.wav';  % Replace with your first file name
file2 = 'scream_looped.wav';  % Replace with your second file name
outputFile = 'combined_audio.wav';

% 1. Read the audio files
[y1, fs1] = audioread(file1);
[y2, fs2] = audioread(file2);

% Check if sampling rates match
if fs1 ~= fs2
    warning('Sampling rates do not match. Resampling file 2 to match file 1...');
    y2 = resample(y2, fs1, fs2);
end

% Ensure both files have the same number of channels (e.g., both stereo or both mono)
% If one is mono and the other is stereo, duplicate the mono channel
if size(y1, 2) == 1 && size(y2, 2) == 2
    y1 = [y1, y1]; 
elseif size(y2, 2) == 1 && size(y1, 2) == 2
    y2 = [y2, y2];
elseif size(y1, 2) ~= size(y2, 2)
    error('Channel mismatch cannot be automatically resolved.');
end

% 2. Make the arrays the same length by zero-padding the shorter one
len1 = size(y1, 1);
len2 = size(y2, 1);
maxLength = max(len1, len2);

if len1 < maxLength
    % Add zeros (silence) to the end of y1
    y1 = [y1; zeros(maxLength - len1, size(y1, 2))];
end

if len2 < maxLength
    % Add zeros (silence) to the end of y2
    y2 = [y2; zeros(maxLength - len2, size(y2, 2))];
end

% 3. Combine the audio signals (mixing)
y_combined = y1 + y2;

% 4. Normalize the audio to prevent clipping
% Adding two signals can result in values outside the valid [-1.0, 1.0] range,
% which causes harsh digital distortion. We scale it back down.
maxVal = max(abs(y_combined(:)));
if maxVal > 1
    y_combined = y_combined / maxVal;
end

% 5. Write the combined audio to a new file
audiowrite(outputFile, y_combined, fs1);

disp('Audio files combined successfully!');