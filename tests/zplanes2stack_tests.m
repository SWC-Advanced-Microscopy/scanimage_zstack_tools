classdef zplanes2stack_tests < matlab.unittest.TestCase
    % Tests associated with building a z-stack and its metadata header
    %
    % Purpose
    % zplanes2stack reads a ScanImage slow stack, registers it and returns a
    % header describing the result. These tests write small synthetic stacks in
    % ScanImage's layout (pages ordered z, then t, then c; a Software tag holding
    % "SI.x = value" lines; a per-frame ImageDescription) and check the header
    % that comes back. Each stack is registered once, in TestClassSetup, because
    % registration dominates the run time.

    properties
        fixtureDir = '';    % Temporary folder holding the synthetic stacks
        runs = struct();    % zplanes2stack outputs for each synthetic stack
    end % properties


    methods(TestClassSetup)
        function buildAndRunStacks(obj)
            fixture = obj.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture);
            obj.fixtureDir = fixture.Folder;

            header = zplanes2stack_tests.fakeHeader();
            stacks = struct( ...
                'stack', header, ...
                'renamed', strrep(header, 'SI.hStackManager.numSlices', 'SI.hStacks.numSlices'));

            for name = fieldnames(stacks)'
                f = fullfile(obj.fixtureDir, [name{1} '.tif']);
                zplanes2stack_tests.writeFakeStack(f, stacks.(name{1}), [0 0 3], [1 2 2]);
                [r.log, r.out, r.channels, r.header] = evalc('zstack.zplanes2stack(f, 1)');
                obj.runs.(name{1}) = r;
            end
        end
    end


    methods(Static)
        function txt = fakeHeader()
            % ScanImage-style Software text for 3 slices x 6 frames x 2 channels
            txt = sprintf([ ...
                'SI.VERSION_MAJOR = 2023\n', ...
                'SI.VERSION_MINOR = 0\n', ...
                'SI.hChannels.channelSave = [1;2]\n', ...
                'SI.hChannels.channelOffset = [0 850]\n', ...
                'SI.hRoiManager.imagingFovUm = [-50 -50;50 -50;50 50;-50 50]\n', ...
                'SI.hRoiManager.linesPerFrame = 96\n', ...
                'SI.hRoiManager.pixelsPerLine = 128\n', ...
                'SI.hRoiManager.scanFrameRate = 30\n', ...
                'SI.hRoiManager.scanZoomFactor = 2\n', ...
                'SI.hScan2D.bidirectional = false\n', ...
                'SI.hScan2D.logAverageFactor = 1\n', ...
                'SI.hScan2D.logFramesPerFile = 10000\n', ...
                'SI.hStackManager.actualStackZStepSize = 2\n', ...
                'SI.hStackManager.framesPerSlice = 6\n', ...
                'SI.hStackManager.numSlices = 3\n', ...
                'SI.hMotors.axesPosition = [6984.38 6664.3 -48540.4]\n', ...
                'SI.hStackManager.stackStartPowerFraction = []\n', ...
                'SI.hStackManager.stackEndPowerFraction = []\n', ...
                'SI.hStackManager.zs = %s\n'], ...
                mat2str(repelem([0 2 4], 6)));
        end


        function writeFakeStack(fileName, softwareText, sliceColShifts, frameRowShifts)
            % Write a 2-channel synthetic stack in ScanImage's page order.
            %
            % sliceColShifts - column shift of each slice's content, one per slice
            % frameRowShifts - [slice frame rowShift] rows: frames moved within a slice
            nFrames = 6;
            rng(42)
            [X,Y] = meshgrid(linspace(-3,3,128), linspace(-3,3,96));
            refImage = 1000 * exp(-(X.^2 + Y.^2)) + ...
                        200 * sin(2*pi*X) .* cos(2*pi*Y);

            tagstruct.ImageLength = size(refImage,1);
            tagstruct.ImageWidth = size(refImage,2);
            tagstruct.Photometric = Tiff.Photometric.MinIsBlack;
            tagstruct.BitsPerSample = 16;
            tagstruct.SamplesPerPixel = 1;
            tagstruct.SampleFormat = Tiff.SampleFormat.Int;
            tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
            tagstruct.Compression = Tiff.Compression.None;
            tagstruct.Software = softwareText;

            t = Tiff(fileName, 'w');
            frameNumber = 0;
            for z = 1:length(sliceColShifts)
                for f = 1:nFrames
                    frameNumber = frameNumber + 1;
                    rowShift = frameRowShifts(frameRowShifts(:,1)==z & frameRowShifts(:,2)==f, 3);
                    if isempty(rowShift)
                        rowShift = 0;
                    end
                    ch1 = circshift(refImage, [rowShift, sliceColShifts(z)]) + 5*randn(size(refImage));
                    frame = cat(3, ch1, 0.5*ch1 + 100);

                    tagstruct.ImageDescription = sprintf( ...
                        'frameNumbers = %d\nepoch = [2026  7  2 17 42 54.802]\ndcOverVoltage = 0\n', ...
                        frameNumber);
                    for c = 1:2
                        if frameNumber > 1 || c > 1
                            t.writeDirectory();
                        end
                        t.setTag(tagstruct);
                        t.write(int16(frame(:,:,c)));
                    end
                end
            end
            t.close();
        end
    end % methods(Static)


    methods
        function folder = newFolder(obj, name)
            % A fresh output folder per test, so each holds one run's log
            folder = fullfile(obj.fixtureDir, name);
            mkdir(folder);
        end

        function txt = readLog(obj, folder)
            % Text of the single zplanes2tiff log in folder
            d = dir(fullfile(folder, 'zplanes2tiff_*.log'));
            obj.assertNumElements(d, 1, sprintf('Expected one zplanes2tiff log in %s', folder))
            txt = fileread(fullfile(folder, d.name));
        end
    end % methods


    methods (Test)
        function headerHasRequestedSIFields(obj)
            requested = { ...
                'SI.VERSION_MAJOR', 'SI.VERSION_MINOR', ...
                'SI.hStackManager.numSlices', 'SI.hStackManager.actualStackZStepSize', ...
                'SI.hStackManager.framesPerSlice', 'SI.hScan2D.logAverageFactor', ...
                'SI.hScan2D.bidirectional', 'SI.hRoiManager.pixelsPerLine', ...
                'SI.hRoiManager.linesPerFrame', 'SI.hRoiManager.scanZoomFactor', ...
                'SI.hRoiManager.scanFrameRate', 'SI.hRoiManager.imagingFovUm', ...
                'SI.hMotors.axesPosition', 'SI.hStackManager.stackStartPowerFraction', ...
                'SI.hStackManager.stackEndPowerFraction'};
            header = obj.runs.stack.header;
            for ii = 1:length(requested)
                obj.verifyTrue(contains(header, [requested{ii} ' = ']), ...
                    sprintf('%s is missing from the header', requested{ii}))
            end
        end

        function headerOmitsOtherFields(obj)
            header = obj.runs.stack.header;
            obj.verifyFalse(contains(header, 'channelOffset'), ...
                'A per-channel setting was copied into the header')
            obj.verifyFalse(contains(header, '.zs = '), ...
                'The per-frame z positions were copied into the header')
        end

        function headerHasEpoch(obj)
            obj.verifyTrue(contains(obj.runs.stack.header, 'epoch = [2026  7  2 17 42 54.802]'), ...
                'The acquisition date (epoch) is missing from the header')
        end

        function headerHasInputsAndDerived(obj)
            header = obj.runs.stack.header;
            expected = { ...
                'zplanes2stack.input.chan = 1', ...
                'zplanes2stack.derived.slicesSaved = 3', ...
                'zplanes2stack.derived.cropEdgePixels = 7'};
            for ii = 1:length(expected)
                obj.verifyTrue(contains(header, expected{ii}), ...
                    sprintf('"%s" is missing from the header', expected{ii}))
            end
        end

        function missingFieldsAreReported(obj)
            r = obj.runs.renamed;
            obj.verifyNotEmpty(r.out, 'A missing header field stopped the run')
            obj.verifyTrue(contains(r.log, 'not present in the ScanImage header') && contains(r.log, 'SI.hStackManager.numSlices'), ...
                'The missing field was not named in the printed output')
            obj.verifyFalse(contains(r.header, 'SI.hStackManager.numSlices'), ...
                'The missing field appeared in the header anyway')
        end


        % zplanes2tiff's run log. These call zplanes2tiff directly rather than
        % through evalc, because output captured by evalc may not reach the diary.

        function logRecordsSuccessfulRun(obj)
            folder = obj.newFolder('logSuccess');
            zstack.zplanes2tiff(fullfile(obj.fixtureDir, 'stack.tif'), 1, ...
                {fullfile(folder, 'a.tiff'), fullfile(folder, 'b.tiff')});
            txt = obj.readLog(folder);
            expected = {'zplanes2tiff started', 'Registering slice 3 of 3', 'Result: SUCCESS'};
            for ii = 1:length(expected)
                obj.verifyTrue(contains(txt, expected{ii}), ...
                    sprintf('"%s" is missing from the log', expected{ii}))
            end
        end

        function logRecordsFailedRun(obj)
            folder = obj.newFolder('logFailed');
            fclose(fopen(fullfile(folder, 'a.tiff'), 'w')); % an output that already exists
            zstack.zplanes2tiff(fullfile(obj.fixtureDir, 'stack.tif'), 1, ...
                {fullfile(folder, 'a.tiff'), fullfile(folder, 'b.tiff')});
            txt = obj.readLog(folder);
            obj.verifyTrue(contains(txt, 'already exists') && contains(txt, 'Result: FAILED'), ...
                'The log does not record the refused run as a failure, with its reason')
            obj.verifyFalse(isfile(fullfile(folder, 'b.tiff')), 'A refused run saved output')
        end

        function logRecordsError(obj)
            folder = obj.newFolder('logError');
            badFile = fullfile(folder, 'noheader.tif'); % a TIFF with no ScanImage header
            t = Tiff(badFile, 'w');
            t.setTag(struct('ImageLength', 8, 'ImageWidth', 8, 'BitsPerSample', 8, ...
                'SamplesPerPixel', 1, 'Photometric', Tiff.Photometric.MinIsBlack, ...
                'PlanarConfiguration', Tiff.PlanarConfiguration.Chunky));
            t.write(zeros(8, 'uint8'));
            t.close();

            errored = false;
            try
                zstack.zplanes2tiff(badFile, 1, {fullfile(folder, 'a.tiff')});
            catch
                errored = true;
            end
            obj.verifyTrue(errored, 'The error was not re-thrown')
            txt = obj.readLog(folder);
            obj.verifyTrue(contains(txt, 'Result: ERROR'), 'The log does not record the error')
            obj.verifyTrue(contains(txt, 'registerAndSave'), ...
                'The log does not say where the error happened')
            obj.verifyFalse(contains(txt, 'matlab.unittest'), ...
                'The log lists stack frames from below zplanes2tiff')
        end

        function previousDiaryIsPausedAndRestored(obj)
            folder = obj.newFolder('logDiary');
            previous = fullfile(folder, 'previous.log');
            diary(previous)
            stopDiary = onCleanup(@() diary('off'));

            fclose(fopen(fullfile(folder, 'a.tiff'), 'w')); % a quick, refused run
            zstack.zplanes2tiff(fullfile(obj.fixtureDir, 'stack.tif'), 1, ...
                {fullfile(folder, 'a.tiff'), fullfile(folder, 'b.tiff')});

            obj.verifyEqual(get(0, 'Diary'), 'on', 'The previous diary was left off')
            obj.verifyEqual(get(0, 'DiaryFile'), previous, 'The previous diary file was not restored')
            diary('off')
            obj.verifyFalse(contains(fileread(previous), 'already exists'), ...
                'The run was written to the previous diary instead of its own log')
        end

        function logRecordsToolboxCommit(obj)
            % The log names the toolbox's git commit, flagging uncommitted changes
            toolboxRoot = fileparts(fileparts(mfilename('fullpath'))); % tests/ is in the toolbox root
            [status, expected] = system(sprintf('git -C "%s" rev-parse --short HEAD', toolboxRoot));
            obj.assumeEqual(status, 0, 'git is not available, so the commit cannot be checked')
            [~, changes] = system(sprintf('git -C "%s" status --porcelain --untracked-files=no', toolboxRoot));

            folder = obj.newFolder('logCommit');
            zstack.zplanes2tiff(fullfile(obj.fixtureDir, 'stack.tif'), 1, ...
                {fullfile(folder, 'a.tiff'), fullfile(folder, 'b.tiff')});
            txt = obj.readLog(folder);

            obj.verifyTrue(contains(txt, ['Toolbox commit: ' strtrim(expected)]), ...
                'The log does not name the toolbox commit')
            obj.verifyEqual(contains(txt, 'with uncommitted changes'), ~isempty(strtrim(changes)), ...
                'The uncommitted-changes note does not match the state of the working tree')
        end

        function missingOutputFolderIsRefused(obj)
            noFolder = fullfile(obj.fixtureDir, 'noSuchFolder');
            [printed, out] = evalc(['zstack.zplanes2tiff(fullfile(obj.fixtureDir, ''stack.tif''), 1, ' ...
                '{fullfile(noFolder, ''a.tiff''), fullfile(noFolder, ''b.tiff'')})']);
            obj.verifyEmpty(out, 'A run with a missing output folder went ahead')
            obj.verifyTrue(contains(printed, 'does not exist') && contains(printed, 'noSuchFolder'), ...
                'The missing folder was not named')
        end
    end % methods (Test)

end % classdef zplanes2stack_tests < matlab.unittest.TestCase
