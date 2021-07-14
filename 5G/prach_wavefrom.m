waveconfig = [];
waveconfig.NumSubframes = 10; % Number of 1 ms subframes in generated waveform
waveconfig.DisplayGrids = 1;  % Display the resource grid
waveconfig.Windowing = [];    % Use the default windowing

% Define a carrier configuration object
carrier = nrCarrierConfig;
carrier.SubcarrierSpacing = 15;
carrier.NSizeGrid = 52;

% Store the carrier into the waveconfig structure
waveconfig.Carriers = carrier;
% PRACH configuration
prach = nrPRACHConfig;
prach.FrequencyRange = 'FR1';   % Frequency range ('FR1', 'FR2')
prach.DuplexMode = 'FDD';       % Duplex mode ('FDD', 'TDD', 'SUL')
prach.ConfigurationIndex = 145; % Configuration index (0...255)
prach.SubcarrierSpacing = 15;   % Subcarrier spacing (1.25, 5, 15, 30, 60, 120)
prach.FrequencyIndex = 0;       % Index of the PRACH transmission occasions in frequency domain (0...7)
prach.TimeIndex = 2;            % Index of the PRACH transmission occasions in time domain (0...6)
prach.ActivePRACHSlot = 0;      % Active PRACH slot number within a subframe or a 60 kHz slot (0, 1)

% Store the PRACH configuration and additional parameters in the
% waveconfig structure
waveconfig.PRACH.Config = prach;
waveconfig.PRACH.AllocatedPreambles = 'all'; % Index of the allocated PRACH preambles
waveconfig.PRACH.Power = 0;   [waveform,gridset,winfo] = hNRPRACHWaveformGenerator(waveconfig);
disp('Information associated with PRACH OFDM modulation for the first PRACH slot:')
disp(gridset.Info(1))

