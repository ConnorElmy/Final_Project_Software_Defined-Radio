% Define your file names and settings
inputFile = 'Kids Children Screaming - Schreiende Kinder - Ringtone Sound Effects - Free Download - Geschrei.wav';         % Replace with your original WAV file
outputFile = 'scream_looped.wav'; % The name of the new file
volumeMultiplier = 1.0;          % 2.0 makes it twice as loud, 1.5 is 50% louder, etc.
repeats = 10;                    % Number of times to loop the audio

% 1. Read the original audio file
[y, fs] = audioread(inputFile);

% 2. Make the audio louder
y_louder = y * volumeMultiplier;

% Prevent clipping (digital distortion)
% If multiplying makes the audio peak above 1.0 or below -1.0, it will sound terrible.
% This caps the audio wave at the absolute maximum limits.
y_louder(y_louder > 1.0) = 1.0;
y_louder(y_louder < -1.0) = -1.0;

% Note: If you want to make it as loud as possible WITHOUT distorting, 
% delete the 5 lines above and use this line instead:
% y_louder = y / max(abs(y(:)));

% 3. Repeat the audio
% repmat (repeat matrix) stacks the audio array vertically 10 times
y_repeated = repmat(y_louder, repeats, 1);

% 4. Write the final audio to a new file
audiowrite(outputFile, y_repeated, fs);

disp('Audio amplified and looped successfully!');