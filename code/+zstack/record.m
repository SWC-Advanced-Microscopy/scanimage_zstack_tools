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
    % Inputs
    % All inputs are optional parameter/value pairs. The user will be interactively
    % prompted at the CLI to fill in any undefined values.
    % 'depthMicrons'      - Total depth to image in microns. Default 250.
    % 'stepSize'          - Number of microns between each z step. Default 2.
    % 'wavelength'        - Excitation wavelength in nm. Default 920.
    %
    %
    % Outputs
    % none
    %
    %
    % Examples
    % 1) Record a 12 micron stack, and prompt user for other inputs.
    % >> zstack.record('depthMicrons',12)
    %
    % 2) Record a 20 micron stack every 0.5 microns.
    % >> zstack.record('depthMicrons',20,'stepSize',0.5);
    %
    %
    % Rob Campbell, SWC AMF, initial commit Nov 2018


    % Parse optional param/value pairs and interactively prompt for anything not
    % supplied. (This was previously handled by a shared parseInputVariable helper.)
    params = inputParser;
    params.CaseSensitive = false; % So we do not have to be case sensitive
    params.KeepUnmatched = true;
    params.addParameter('wavelength', [], @(x) isnumeric(x));
    params.addParameter('depthMicrons', [], @(x) isnumeric(x));
    params.addParameter('stepSize', [], @(x) isnumeric(x));
    params.parse(varargin{:});

    laser_wavelength = params.Results.wavelength;
    micronsToImage = params.Results.depthMicrons;
    stepSizeInMicrons = params.Results.stepSize;

    % Interactively handle each input argument if it was not supplied as a param/val pair
    if isempty(micronsToImage)
        default = 250;
        txt = sprintf('Please enter depth (um) [%d]: ', default);
        micronsToImage = round(parseResponse(txt, default));
    end

    if isempty(stepSizeInMicrons)
        default = 2;
        txt = sprintf('Please enter step size (um) [%d]: ', default);
        stepSizeInMicrons = parseResponse(txt, default);
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


    if length(API.hSI.hChannels.channelSave) > 1
        fprintf('Select just one channel to save\n')
        return
    end

    % Save into the current directory
    saveDir = pwd;


    %Record the state of all ScanImage settings we will change so we can change them back
    initialSettings = recordScanImageSettings(API);

    % We will set up ScanImage to acquire the z-stack
    framesToAverage = API.hSI.hDisplay.displayRollingAverageFactor;
    numSlices = round(micronsToImage/stepSizeInMicrons);
    fileStem = sprintf('zstack__%d_nm__%s', ....
            laser_wavelength, ...
            datestr(now,'yyyy-mm-dd_HH-MM-SS'));

    try

        if API.versionGreaterThan('2020')
            API.hSI.hStackManager.closeShutterBetweenSlices = false;
            API.hSI.hStackManager.numVolumes = 1;
            API.hSI.hStackManager.stackActuator = 'fastZ';
            API.hSI.hStackManager.centeredStack = 0;
            API.hSI.hStackManager.enable = true;
        else
            API.hSI.hFastZ.enable=false;
            API.hSI.hFastZ.numVolumes=1;
            API.hSI.hStackManager.stackStartCentered=false; %TODO: SI doesn't work correctly when true
            API.hSI.hStackManager.shutterCloseMinZStepSize=stepSizeInMicrons+1;
            API.hSI.hStackManager.slowStackWithFastZ=true;
        end
        %%
        API.hSI.hFastZ.waveformType='step';


        API.hSI.hStackManager.numSlices=numSlices;
        API.hSI.hStackManager.stackZStepSize=stepSizeInMicrons;

        API.hSI.hChannels.loggingEnable=true;

        API.hSI.hScan2D.logFileStem=fileStem;
        API.hSI.hScan2D.logFilePath=saveDir;
        API.hSI.hScan2D.logFileCounter=1;

        API.hSI.hStackManager.framesPerSlice = framesToAverage;
        API.hSI.hScan2D.logAverageFactor = framesToAverage;
        API.hSI.hScan2D.bidirectional = 0; % disable bidi to avoid bidi artifacts in stacks

        API.hSI.hDisplay.volumeDisplayStyle='Current';
    catch ME
        %If something went wrong we revert the scan settings
        fprintf('Failed to set scan settings\n')
        fprintf(ME.message)
        return
    end

    % Start the acquisition and wait for it to finish
    API.acquireAndWait;

    % Report where the file was saved
    D = dir([fullfile(saveDir,fileStem),'*']);
    if ~isempty(D)
        fprintf('Saved data to %s\n', fullfile(saveDir,D(1).name))
    end


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
