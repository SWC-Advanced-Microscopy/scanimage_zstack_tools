classdef zplanes2stack_tests < matlab.unittest.TestCase
    % Tests associated with building a z-stack and its metadata
    %
    % Purpose
    % zplanes2stack reads a ScanImage slow stack, registers it and returns a
    % metadata struct describing the result; zplanes2tiff saves it as each TIFF's
    % Software tag and as a JSON file. These tests write small synthetic stacks in
    % ScanImage's layout (pages ordered z, then t, then c; a Software tag holding
    % "SI.x = value" lines; a per-frame ImageDescription) and check the metadata
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

            % The header says 4 slices, but only 3 were recorded
            truncated = strrep(header, 'numSlices = 3', 'numSlices = 4');
            truncated = strrep(truncated, mat2str(repelem([0 2 4], 6)), mat2str(repelem([0 2 4 6], 6)));

            % Name, header text and the column shift of each slice's content.
            % In every stack, frame 2 of slice 1 is shifted 2 rows.
            stacks = { ...
                'stack',     header,                                                                   [0 0 3]; ...
                'renamed',   strrep(header, 'SI.hStackManager.numSlices', 'SI.hStacks.numSlices'),    [0 0 3]; ...
                'truncated', truncated,                                                                [0 0 3]; ...
                'nozs',      regexprep(header, 'SI\.hStackManager\.zs = [^\n]*\n', ''),              [0 0 3]; ...
                'averagedzs', strrep(header, 'logAverageFactor = 1', 'logAverageFactor = 2'),         [0 0 3]; ...
                'accumulate', header,                                                                 [0 3 3]; ...
                'bigstep',   header,                                                                   [0 0 12]};

            for ii = 1:size(stacks, 1)
                f = fullfile(obj.fixtureDir, [stacks{ii,1} '.tif']);
                zplanes2stack_tests.writeFakeStack(f, stacks{ii,2}, stacks{ii,3}, [1 2 2]);
                [r.log, r.out, r.channels, r.meta, r.slices] = evalc('zstack.zplanes2stack(f, 1)');
                obj.runs.(stacks{ii,1}) = r;
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


        function tf = hasPath(s, name)
            % True if the dotted field name (e.g. 'SI.hStackManager.numSlices') exists in s
            tf = true;
            for part = strsplit(name, '.')
                if ~isstruct(s) || ~isfield(s, part{1})
                    tf = false;
                    return
                end
                s = s.(part{1});
            end
        end

        function [names, values] = leaves(s, prefix)
            % Dotted names and values of every non-struct field in s
            names = {};
            values = {};
            for f = fieldnames(s)'
                v = s.(f{1});
                if isstruct(v)
                    [n, vals] = zplanes2stack_tests.leaves(v, [prefix f{1} '.']);
                    names = [names, n]; %#ok<AGROW>
                    values = [values, vals]; %#ok<AGROW>
                else
                    names{end+1} = [prefix f{1}]; %#ok<AGROW>
                    values{end+1} = v; %#ok<AGROW>
                end
            end
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
        function metaHasRequestedSIFields(obj)
            requested = { ...
                'SI.VERSION_MAJOR', 'SI.VERSION_MINOR', ...
                'SI.hStackManager.numSlices', 'SI.hStackManager.actualStackZStepSize', ...
                'SI.hStackManager.framesPerSlice', 'SI.hScan2D.logAverageFactor', ...
                'SI.hScan2D.bidirectional', 'SI.hRoiManager.pixelsPerLine', ...
                'SI.hRoiManager.linesPerFrame', 'SI.hRoiManager.scanZoomFactor', ...
                'SI.hRoiManager.scanFrameRate', 'SI.hRoiManager.imagingFovUm', ...
                'SI.hMotors.axesPosition', 'SI.hStackManager.stackStartPowerFraction', ...
                'SI.hStackManager.stackEndPowerFraction'};
            for ii = 1:length(requested)
                obj.verifyTrue(zplanes2stack_tests.hasPath(obj.runs.stack.meta, requested{ii}), ...
                    sprintf('%s is missing from the metadata', requested{ii}))
            end
            obj.verifyEqual(obj.runs.stack.meta.SI.hStackManager.numSlices, 3, ...
                'numSlices was not read as a number')
            obj.verifyEqual(obj.runs.stack.meta.epoch, [2026 7 2 17 42 54.802], ...
                'The acquisition date (epoch) is missing or wrong')
        end

        function metaHasInputsAndDerived(obj)
            meta = obj.runs.stack.meta;
            obj.verifyTrue(zplanes2stack_tests.hasPath(meta, 'zplanes2stack.input.chan') && ...
                zplanes2stack_tests.hasPath(meta, 'zplanes2stack.derived.slicesSaved'), ...
                'The inputs or derived values are missing from the metadata')
            obj.verifyEqual(meta.zplanes2stack.input.chan, 1)
            obj.verifyEqual(meta.zplanes2stack.input.refine, false)
            obj.verifyEqual(meta.zplanes2stack.derived.slicesSaved, 3)
            obj.verifyEqual(meta.zplanes2stack.derived.cropEdgePixels, 7)
        end

        function missingFieldsAreReported(obj)
            r = obj.runs.renamed;
            obj.verifyNotEmpty(r.out, 'A missing header field stopped the run')
            obj.verifyTrue(contains(r.log, 'not present in the ScanImage header') && contains(r.log, 'SI.hStackManager.numSlices'), ...
                'The missing field was not named in the printed output')
            obj.verifyTrue(isstruct(r.meta), 'The metadata is not a struct')
            obj.verifyFalse(zplanes2stack_tests.hasPath(r.meta, 'SI.hStackManager.numSlices'), ...
                'The missing field appeared in the metadata anyway')
        end


        % zplanes2tiff's saved metadata: Software tag and JSON

        function jsonMatchesSoftwareTag(obj)
            folder = obj.newFolder('json');
            [~, ~, meta] = zstack.zplanes2tiff(fullfile(obj.fixtureDir, 'stack.tif'), 1, ...
                {fullfile(folder, 'a.tiff'), fullfile(folder, 'b.tiff')});
            meta.zplanes2stack.derived.channel = 1; % what a.tiff should hold

            obj.assertTrue(isfile(fullfile(folder, 'a.json')), 'No JSON file was written')
            json = jsondecode(fileread(fullfile(folder, 'a.json')));
            software = imfinfo(fullfile(folder, 'a.tiff')).Software;

            [names, values] = zplanes2stack_tests.leaves(meta, '');
            for ii = 1:length(names)
                obj.verifyTrue(zplanes2stack_tests.hasPath(json, names{ii}), ...
                    sprintf('%s is missing from the JSON', names{ii}))
                if zplanes2stack_tests.hasPath(json, names{ii})
                    parts = strsplit(names{ii}, '.');
                    obj.verifyEqual(double(reshape(getfield(json, parts{:}), [], 1)), double(values{ii}(:)), ...
                        'AbsTol', 1e-12, sprintf('%s differs between the JSON and the metadata', names{ii}))
                end
                obj.verifyTrue(contains(software, [names{ii} ' = ' mat2str(values{ii})]), ...
                    sprintf('%s is missing from, or differs in, the Software tag', names{ii}))
            end

            % The second file holds channel 2, in both its JSON and Software tag
            jsonB = jsondecode(fileread(fullfile(folder, 'b.json')));
            obj.verifyEqual(jsonB.zplanes2stack.derived.channel, 2, 'b.json does not say channel 2')
            infoB = imfinfo(fullfile(folder, 'b.tiff')); % one entry per page
            obj.verifyTrue(contains(infoB(1).Software, 'zplanes2stack.derived.channel = 2'), ...
                'b.tiff''s Software tag does not say channel 2')
        end

        function sidecarsGoNextToTheirTiffs(obj)
            % Each JSON goes next to its TIFF; the slice table (default name)
            % goes next to the first output
            folder = obj.newFolder('sidecarPaths');
            mkdir(fullfile(folder, 'sub'));
            zstack.zplanes2tiff(fullfile(obj.fixtureDir, 'stack.tif'), 1, ...
                {fullfile(folder, 'sub', 'a.tiff'), fullfile(folder, 'b')});
            obj.verifyTrue(isfile(fullfile(folder, 'sub', 'a.json')), 'a.json is not next to sub/a.tiff')
            obj.verifyTrue(isfile(fullfile(folder, 'b.json')), 'b.json is not next to b (no extension)')
            obj.verifyTrue(isfile(fullfile(folder, 'sub', 'slices.csv')), ...
                'The slice table is not slices.csv beside the first output')
        end

        function existingSidecarIsRefusedBeforeRunning(obj)
            % An existing JSON file or slice table stops the run before anything
            % is saved (an existing TIFF is covered by logRecordsFailedRun)
            for existing = {'a.json', 'slices.csv'}
                folder = obj.newFolder(['exists_' strrep(existing{1}, '.', '_')]);
                fclose(fopen(fullfile(folder, existing{1}), 'w'));
                [printed, out] = evalc(['zstack.zplanes2tiff(fullfile(obj.fixtureDir, ''stack.tif''), 1, ' ...
                    '{fullfile(folder, ''a.tiff''), fullfile(folder, ''b.tiff'')})']);
                obj.verifyEmpty(out, sprintf('A run whose %s already exists went ahead', existing{1}))
                obj.verifyTrue(contains(printed, 'already exists') && contains(printed, existing{1}), ...
                    sprintf('The existing %s was not named', existing{1}))
                obj.verifyFalse(isfile(fullfile(folder, 'a.tiff')), 'A refused run saved output')
            end
        end

        function fileElsewhereOnPathDoesNotBlockSaving(obj)
            % A file of the same name in a folder on the MATLAB path isn't the
            % output file, so it mustn't stop the save (it once did, after
            % registration had run)
            onPath = obj.newFolder('onPath');
            fclose(fopen(fullfile(onPath, 'a.tiff'), 'w'));
            obj.applyFixture(matlab.unittest.fixtures.PathFixture(onPath));
            runHere = obj.newFolder('runHere');
            obj.applyFixture(matlab.unittest.fixtures.CurrentFolderFixture(runHere));

            zstack.zplanes2tiff(fullfile(obj.fixtureDir, 'stack.tif'), 1, {'a.tiff', 'b.tiff'});
            obj.verifyTrue(isfile(fullfile(runHere, 'a.tiff')) && isfile(fullfile(runHere, 'b.tiff')), ...
                'The outputs were not saved in the current folder')
        end


        % The per-slice table

        function sliceTableColumns(obj)
            slices = obj.runs.stack.slices;
            obj.assertTrue(istable(slices), 'No slice table was returned')
            obj.verifyEqual(slices.Properties.VariableNames, ...
                {'slice', 'zUm', 'shiftXPx', 'shiftYPx', 'stepXPx', 'stepYPx', 'framesAtZeroShiftWithinSlice'})
            obj.verifyEqual(height(slices), 3)
            obj.verifyEqual(slices.slice, [1; 2; 3])
        end

        function zPositionsFollowHeader(obj)
            obj.verifyEqual(obj.runs.stack.slices.zUm, [0; 2; 4], ...
                'zUm is not the z position of each slice''s first frame')
            obj.verifyFalse(contains(obj.runs.stack.log, 'zUm is NaN'), ...
                'A problem with the z positions was reported when there was none')

            % No z positions in the header
            r = obj.runs.nozs;
            obj.verifyNotEmpty(r.out, 'A header without z positions stopped the run')
            obj.verifyTrue(all(isnan(r.slices.zUm)), 'zUm should be NaN without z positions')
            obj.verifyTrue(contains(r.log, 'zUm is NaN'), 'The missing z positions were not reported')
        end

        function averagedStackHasNoZUm(obj)
            % With frames saved averaged, it isn't yet known whether zs counts
            % frames acquired or saved, so zUm is left as NaN and reported
            r = obj.runs.averagedzs;
            obj.verifyTrue(all(isnan(r.slices.zUm)), ...
                sprintf('zUm should be NaN, not %s', mat2str(r.slices.zUm')))
            obj.verifyTrue(contains(r.log, 'zUm is NaN'), 'The reason zUm is NaN was not reported')
        end

        function noCompleteSlicesFailsCleanly(obj)
            % The header says 12 frames per slice, but only 6 frames' pages
            % were recorded, so not even the first slice is complete
            f = fullfile(obj.fixtureDir, 'noslices.tif');
            header = strrep(zplanes2stack_tests.fakeHeader(), 'framesPerSlice = 6', 'framesPerSlice = 12');
            zplanes2stack_tests.writeFakeStack(f, header, 0, [1 2 2]);
            [printed, out] = evalc('zstack.zplanes2stack(f, 1)');
            obj.verifyEmpty(out, 'A stack with no complete slices returned output')
            obj.verifyTrue(contains(printed, 'No complete slices'), 'The reason was not reported')
        end

        function shiftsAreRelativeToSlice1(obj)
            % Slices 2 and 3 are both 3 px right of slice 1, so both are shifted
            % back by 3 px; only slice 2 has moved from its neighbour
            slices = obj.runs.accumulate.slices;
            obj.verifyEqual(slices.shiftXPx, [0; -3; -3], 'AbsTol', 0.5, ...
                'Shifts are not relative to slice 1')
            obj.verifyEqual(slices.stepXPx, [0; -3; 0], 'AbsTol', 0.5, ...
                'Steps are not relative to the previous slice')
            obj.verifyEqual(slices.stepYPx, [0; 0; 0], 'AbsTol', 0.5, 'No slice moved in y')
        end

        function largeStepIsReported(obj)
            obj.verifyTrue(contains(obj.runs.bigstep.log, 'Slice 3 moved'), ...
                'A 12 px step between slices was not reported')
            obj.verifyFalse(contains(obj.runs.stack.log, 'moved'), ...
                'A 3 px step between slices was reported')
        end

        function truncatedStackHasOneRowPerSavedSlice(obj)
            r = obj.runs.truncated;
            obj.verifyEqual(r.meta.zplanes2stack.derived.slicesSaved, 3)
            obj.verifyEqual(height(r.slices), 3, 'The table should only list the slices kept')
            obj.verifyEqual(r.slices.zUm, [0; 2; 4])
        end

        function sliceTableIsWrittenAsCsvOrTsv(obj)
            folder = obj.newFolder('sliceCsv');
            zstack.zplanes2tiff(fullfile(obj.fixtureDir, 'stack.tif'), 1, ...
                {fullfile(folder, 'a.tiff'), fullfile(folder, 'b.tiff')}, 'sliceFile', fullfile(folder, 's.csv'));
            obj.assertTrue(isfile(fullfile(folder, 's.csv')), 'No slice table was written')
            written = readtable(fullfile(folder, 's.csv'));
            obj.verifyEqual(height(written), 3)
            obj.verifyEqual(written.Properties.VariableNames, obj.runs.stack.slices.Properties.VariableNames)

            % .tsv, in any case, gives a tab-separated file
            folder = obj.newFolder('sliceTsv');
            zstack.zplanes2tiff(fullfile(obj.fixtureDir, 'stack.tif'), 1, ...
                {fullfile(folder, 'a.tiff'), fullfile(folder, 'b.tiff')}, 'sliceFile', fullfile(folder, 's.TSV'));
            obj.assertTrue(isfile(fullfile(folder, 's.TSV')), 'No .TSV slice table was written')
            firstLine = strtok(fileread(fullfile(folder, 's.TSV')), newline);
            obj.verifyTrue(contains(firstLine, sprintf('\t')), 'The .TSV file is not tab-separated')
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

            % The result line lists every file saved
            lines = splitlines(txt);
            resultLine = lines(startsWith(lines, 'Result:'));
            obj.assertNotEmpty(resultLine, 'The log has no Result line')
            for f = {'a.tiff', 'b.tiff', 'a.json', 'b.json', 'slices.csv'}
                obj.verifyTrue(contains(resultLine{1}, f{1}), ...
                    sprintf('The Result line does not list %s', f{1}))
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
