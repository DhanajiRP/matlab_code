numSubframes = 10;               % Number of 1 ms subframes to simulate at each SNR
SNRdB = [-21, -16, -11, -6, -1]; % SNR range in dB
foffset = 400.0;                 % Frequency offset in Hz
timeErrorTolerance = 2.55;       % Time error tolerance in microseconds
carrier = nrCarrierConfig;
carrier.SubcarrierSpacing = 15;
carrier.NSizeGrid = 25;
% Define the value of ZeroCorrelationZone using the NCS table stored in
% the |nrPRACHConfig| object
ncsTable = nrPRACHConfig.Tables.NCSFormat012;
NCS = 13;
zeroCorrelationZone = ncsTable.ZeroCorrelationZone(ncsTable.UnrestrictedSet==NCS);

% Set PRACH configuration
prach = nrPRACHConfig;
prach.FrequencyRange = 'FR1';                    % Frequency range
prach.DuplexMode = 'FDD';                        % Frequency Division Duplexing (FDD)
prach.ConfigurationIndex = 27;                   % Configuration index for format 0
prach.SubcarrierSpacing = 1.25;                  % Subcarrier spacing
prach.SequenceIndex = 22;                        % Logical sequence index
prach.PreambleIndex = 32;                        % Preamble index
prach.RestrictedSet = 'UnrestrictedSet';         % Normal mode
prach.ZeroCorrelationZone = zeroCorrelationZone; % Cyclic shift index
prach.FrequencyStart = 0;                        % Frequency location

% Compute the OFDM-related information for this PRACH configuration
windowing = [];
ofdmInfo = nrPRACHOFDMInfo(carrier,prach,'Windowing',windowing);
channel = nrTDLChannel;
channel.DelayProfile = "TDL-C";             % Delay profile
channel.DelaySpread = 300e-9;               % Delay spread in seconds
channel.MaximumDopplerShift = 100.0;        % Maximum Doppler shift in Hz
channel.SampleRate = ofdmInfo.SampleRate;   % Input signal sample rate in Hz
channel.MIMOCorrelation = "Low";            % MIMO correlation
channel.TransmissionDirection = "Uplink";   % Uplink transmission
channel.NumTransmitAntennas = 1;            % Number of transmit antennas
channel.NumReceiveAntennas = 2;             % Number of receive antennas
channel.NormalizePathGains = true;          % Normalize delay profile power
channel.Seed = 42;                          % Channel seed. Change this for different channel realizations
channel.NormalizeChannelOutputs = true;     % Normalize for receive antennas
% Initialize variables storing probability of detection at each SNR
pDetection = zeros(size(SNRdB));

% Get the maximum number of delayed samples by a channel multipath
% component. This is calculated from the channel path with the largest
% delay and the implementation delay of the channel filter. The example
% requires this to flush the channel filter to obtain the received signal.
channelInfo = info(channel);
maxChDelay = ceil(max(channelInfo.PathDelays*channel.SampleRate)) + channelInfo.ChannelFilterDelay;

% Total number of PRACH slots in the simulation period
numPRACHSlots = floor(numSubframes / prach.SubframesPerPRACHSlot);

% Store the configuration parameters needed to generate the PRACH waveform
waveconfig.NumSubframes = prach.SubframesPerPRACHSlot;
waveconfig.Windowing = windowing;
waveconfig.Carriers = carrier;
waveconfig.PRACH.Config = prach;

% The temporary variables 'prach_init', 'waveconfig_init', 'ofdmInfo_init',
% and 'channelInfo_init' are used to create the temporary variables
% 'prach', 'waveconfig', 'ofdmInfo', and 'channelInfo' within the SNR loop
% to create independent instances in case of parallel simulation
prach_init = prach;
waveconfig_init = waveconfig;
ofdmInfo_init = ofdmInfo;
channelInfo_init = channelInfo;

for snrIdx = 1:numel(SNRdB) % comment out for parallel computing
% parfor snrIdx = 1:numel(SNRdB) % uncomment for parallel computing
% To reduce the total simulation time, you can execute this loop in
% parallel by using the Parallel Computing Toolbox. Comment out the 'for'
% statement and uncomment the 'parfor' statement. If the Parallel Computing
% Toolbox(TM) is not installed, 'parfor' defaults to normal 'for' statement

    % Set the random number generator settings to default values
    rng('default');

    % Initialize variables for this SNR point, required for initialization
    % of variables when using the Parallel Computing Toolbox
    prach = prach_init;
    waveconfig = waveconfig_init;
    ofdmInfo = ofdmInfo_init;
    channelInfo = channelInfo_init;

    % Reset the channel so that each SNR point will experience the same
    % channel realization
    reset(channel);

    % Normalize noise power to take account of sampling rate, which is a
    % function of the IFFT size used in OFDM modulation. The SNR is defined
    % per resource element for each receive antenna.
    SNR = 10^(SNRdB(snrIdx)/20);
    N0 = 1/(sqrt(2.0*channel.NumReceiveAntennas*double(ofdmInfo.Nfft))*SNR);

    % Detected preamble count
    detectedCount = 0;

    % Loop for each PRACH slot
    numActivePRACHSlots = 0;
    for nSlot = 0:numPRACHSlots-1

        prach.NPRACHSlot = nSlot;

        % Generate PRACH waveform for the current slot
        waveconfig.PRACH.Config.NPRACHSlot = nSlot;
        [waveform,~,winfo] = hNRPRACHWaveformGenerator(waveconfig);

        % Skip this slot if the PRACH is inactive
        if (isempty(winfo.WaveformResources.PRACH))
            continue;
        end

        numActivePRACHSlots = numActivePRACHSlots + 1;

        % Set PRACH timing offset in microseconds as per TS 38.141-1 Figure 8.4.1.4.2-2
        baseOffset = ((winfo.WaveformResources.PRACH.Resources.PRACHSymbolsInfo.NumCyclicShifts/2)/prach.LRA)/prach.SubcarrierSpacing*1e3; % (microseconds)
        timingOffset = baseOffset + mod(nSlot,10)/10; % (microseconds)
        sampleDelay = fix(timingOffset / 1e6 * ofdmInfo.SampleRate);

        % Generate transmit waveform
        txwave = [zeros(sampleDelay,1); waveform(1:(end-sampleDelay))];

        % Pass data through channel model. Append zeros at the end of the
        % transmitted waveform to flush channel content. These zeros take
        % into account any delay introduced in the channel. This is a mix
        % of multipath delay and implementation delay. This value may
        % change depending on the sampling rate, delay profile and delay
        % spread
        rxwave = channel([txwave; zeros(maxChDelay, size(txwave,2))]);

        % Add noise
        noise = N0*complex(randn(size(rxwave)), randn(size(rxwave)));
        rxwave = rxwave + noise;

        % Remove the implementation delay of the channel modeling
        rxwave = rxwave((channelInfo.ChannelFilterDelay + 1):end, :);

        % Apply frequency offset
        t = ((0:size(rxwave, 1)-1)/channel.SampleRate).';
        rxwave = rxwave .* repmat(exp(1i*2*pi*foffset*t), 1, size(rxwave, 2));

        % PRACH detection for all cell preamble indices
        [detected, offsets] = hPRACHDetect(carrier, prach, rxwave, (0:63).');

        % Test for preamble detection
        if (length(detected)==1)

            % Test for correct preamble detection
            if (detected==prach.PreambleIndex)

                % Calculate timing estimation error
                trueOffset = timingOffset/1e6; % (s)
                measuredOffset = offsets(1)/channel.SampleRate;
                timingerror = abs(measuredOffset-trueOffset);

                % Test for acceptable timing error
                if (timingerror<=timeErrorTolerance/1e6)
                    detectedCount = detectedCount + 1; % Detected preamble
                else
                    disp('Timing error');
                end
            else
                disp('Detected incorrect preamble');
            end
        else
            disp('Detected multiple or zero preambles');
        end

    end % of nSlot loop

    % Compute final detection probability for this SNR
    pDetection(snrIdx) = detectedCount/numActivePRACHSlots;

end % of SNR loop
hPRACHDetectionResults(SNRdB, numSubframes, pDetection);
