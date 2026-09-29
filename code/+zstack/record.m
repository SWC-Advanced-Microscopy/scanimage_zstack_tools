function record(varargin)
    % Record a z-stack
    %
    %  zstack.record('param1','val1', ...)
    %
    % Purpose
    % This function simplifies setting up ScanImage to acquire a z-stack. The user
    % defines the depth of the stack in microns and the separation between planes
    % within this function and ScanImage is set up appropriately. The image stack is
    % averaged using the number of frames entered in the ScanImage IMAGE CONTROLS
    % window. The path to the saved data is displayed to screen. Data are saved into
    % the current directory.
    %
    %
    % INSTRUCTIONS
    % 1. Check 'Enable Stack' in the main ScanImage Window.
    % 2. Go to 'Stack Controls' and go to the 'Bounded' tab.
    % 3. Navigate to brain surface or just above. Set laser power. Set the start step (clear first if needed)
    % 4. Navigate to the lowest depth you will image. Set the end.
    % 5. Run this command.
    %
    %
    % Inputs
    % All inputs are optional parameter/value pairs.
    % prompted at the CLI to fill in any undefined values.
    % 'stepSize'          - Number of microns between each z step. Default 2.
    % 'framesToAverage'   - By default is 64
    % 'wavelength'        - Excitation wavelength in nm. Default 920.
    %
    %
    % Outputs
    % none
    %
    %
    % NOTE
    % 1. ScanImage 2020 or later
    % 2. You must have a coarse z motor and it must be working and the units must be in microns
    %
    %
    % Examples
    % 1) Record a 20 micron stack every 2 microns.
    % >> zstack.record('stepSize',2);
    %
    %
    % Rob Campbell, SWC AMF, initial commit July 2026
    % Based on mpqc.record.PSF (original Nov 2018)


    % Parse optional param/value pairs and interactively prompt for anything not
    % supplied. (This was previously handled by a shared parseInputVariable helper.)
    params = inputParser;
    params.CaseSensitive = false; % So we do not have to be case sensitive
    params.KeepUnmatched = true;
    params.addParameter('wavelength', [], @(x) isnumeric(x));
    params.addParameter('framesToAverage', 64, @(x) isnumeric(x));
    params.addParameter('stepSize', 2, @(x) isnumeric(x));
    params.parse(varargin{:});

    laser_wavelength = params.Results.wavelength;
    framesToAverage = params.Results.framesToAverage;
    stepSizeInMicrons = params.Results.stepSize;


    % ensure framesToAverage is divisble by 2, because we will average
    % adjacent frames to save space
    framesToAverage = ceil(framesToAverage/2)*2;


    % Interactively handle each input argument if it was not supplied as a param/val pair
    if isempty(stepSizeInMicrons)
        default = 4;
    end

    if isempty(laser_wavelength)
        default = 920;
        txt = sprintf('Please enter wavelength (nm) [%d]: ', default);
        laser_wavelength = round(parseResponse(txt, default));
    end


    % Connect to ScanImage using the linker class
    API = sibridge.silinker;

    if API.linkSucceeded == false
        return
    end


    % Use the bounded stack to run the acquisition
    startPos = API.hSI.hStackManager.stackZStartPos;
    endPos = API.hSI.hStackManager.stackZEndPos;
    API.hSI.hStackManager.useStartEndPowers=true; %ensure user choices honoured

    micronsToImage = abs(startPos-endPos);
    numSlices = ceil(micronsToImage / stepSizeInMicrons);

    % record if downward objective motions are positive or negative
    % we need this later for pre-loading the coarse z
    if startPos<endPos
        downwardMotionSign = 1;
    else
        downwardMotionSign = -1;
    end


    % Save into the current directory
    saveDir = pwd;


    %Record the state of all ScanImage settings we will change so we can change them back
    initialSettings = recordScanImageSettings(API);

    % We will set up ScanImage to acquire the z-stack
    API.hSI.hDisplay.displayRollingAverageFactor = framesToAverage;

    numSlices = round(micronsToImage/stepSizeInMicrons);
    fileStem = sprintf('zstack__%d_nm__%s', ....
            laser_wavelength, ...
            datestr(now,'yyyy-mm-dd_HH-MM-SS'));

    try

        API.hSI.hStackManager.closeShutterBetweenSlices = false;
        API.hSI.hStackManager.numVolumes = 1;
        API.hSI.hStackManager.stackActuator = 'motor';
        API.hSI.hStackManager.centeredStack = 0;
        API.hSI.hStackManager.enable = true;

        %%
        %API.hSI.hFastZ.waveformType='step';


        API.hSI.hStackManager.numSlices=numSlices;
        API.hSI.hStackManager.stackZStepSize=stepSizeInMicrons;

        API.hSI.hChannels.loggingEnable=true;

        API.hSI.hScan2D.logFileStem=fileStem;
        API.hSI.hScan2D.logFilePath=saveDir;
        API.hSI.hScan2D.logFileCounter=1;

        API.hSI.hStackManager.framesPerSlice = framesToAverage;

        % We will average adjacent frames meaning final size on disk will be half what it would
        % otherwise be. On a typical resonant scanning rig that means 7 to 10 FPS (since we disable bidi)
        API.hSI.hScan2D.logAverageFactor = 2;

        API.hSI.hScan2D.bidirectional = 0; % disable bidi to avoid bidi artifacts in stacks

        API.hSI.hDisplay.volumeDisplayStyle='Current';
    catch ME
        %If something went wrong we revert the scan settings
        fprintf('Failed to set scan settings\n')
        fprintf(ME.message)
        return
    end


    % Pre-load coarse z motors (we assume Z is on 3) and units in microns
    allMotorsCurrent = API.hSI.hMotors.samplePosition;

    % Go to the start Z pos, as we may well not be there yet
    allMotorsCurrent(3) = startPos;
    API.hSI.hMotors.moveSample(allMotorsCurrent);


    % Now move a good deal UP then back down to pre-load the motor
    currentZMotorPos = API.hSI.hMotors.samplePosition(3);
    targetZMotorPos = currentZMotorPos - (700*downwardMotionSign);

    allMotorsTarget = allMotorsCurrent;
    allMotorsTarget(3) = targetZMotorPos;

    API.hSI.hMotors.moveSample(allMotorsTarget);
    API.hSI.hMotors.moveSample(allMotorsCurrent);

    pause(1)

    % Start the acquisition and wait for it to finish
    API.acquireAndWait;

    % Report where the file was saved
    D = dir([fullfile(saveDir,fileStem),'*']);
    if ~isempty(D)
        fprintf('Saved data to %s\n', fullfile(saveDir,D(1).name))
    end


    % TODO -- apply this in a cleanup function
    reapplyScanImageSettings(API,initialSettings);

end % zstack.record



function response = parseResponse(promptString,default)
    % Conducts an interactive prompt to help the user choose a value

    response = [];
    while isempty(response)
        response = input(promptString,'s');
        if isempty(response)
            response = default;
        else
            response = str2num(response);
        end
   end
end % parseResponse

