classdef registration_tests < matlab.unittest.TestCase
    % Tests associated with the FFT translation registration
    %
    % Purpose
    % With the default upsampling factor of 1 the registration is a whole-pixel
    % circular shift, which is a pure permutation of the pixels. That gives us an
    % exact invariant to test against: registering a circularly shifted frame must
    % return the original frame with its pixel values untouched. These tests use
    % that invariant to confirm that no rectification or re-scaling is applied to
    % the data, which matters because ScanImage writes signed data and we high-pass
    % filter before registering.
    %
    %
    % Rob Campbell - SWC 2026

    properties
        refImage = [];      % The reference (target) image
        shifts = [ 0,  0; ...
                   3, -5; ...
                  -7, 11; ...
                  12,  8];  % Row/column shifts applied to make the test stack
    end % properties


    methods(TestClassSetup)
        function buildReferenceImage(obj)
            % A smooth, structured image so the correlation peak is unambiguous
            rng(42)
            [X,Y] = meshgrid(linspace(-3,3,128), linspace(-3,3,96)); % non-square on purpose
            obj.refImage = 1000 * exp(-(X.^2 + Y.^2)) + ...
                            200 * sin(2*pi*X) .* cos(2*pi*Y) + ...
                             10 * randn(size(X));
        end
    end




    methods

        function stack = makeShiftedStack(obj, im)
            % Build a stack by circularly shifting im by each row of obj.shifts
            stack = zeros([size(im), size(obj.shifts,1)]);
            for ii = 1:size(obj.shifts,1)
                stack(:,:,ii) = circshift(im, obj.shifts(ii,:));
            end
        end

    end % methods




    methods (Test)

        function registrationRecoversTheOriginalFrames(obj)
            % Each shifted frame must come back equal to the reference image
            stack = obj.makeShiftedStack(obj.refImage);
            reg = zstack.registration.applyShifts(stack, zstack.registration.findShifts(stack, obj.refImage));

            for ii = 1:size(stack,3)
                obj.verifyEqual(reg(:,:,ii), obj.refImage, 'AbsTol', 1e-6, ...
                    sprintf('Frame %d was not restored to the reference image', ii))
            end
        end


        function pixelValuesArePreserved(obj)
            % A whole-pixel shift permutes pixels, so the sorted values must match
            stack = obj.makeShiftedStack(obj.refImage);
            reg = zstack.registration.applyShifts(stack, zstack.registration.findShifts(stack, obj.refImage));

            for ii = 1:size(stack,3)
                obj.verifyEqual(sort(reshape(reg(:,:,ii),[],1)), ...
                                sort(obj.refImage(:)), 'AbsTol', 1e-6, ...
                    sprintf('Frame %d had its pixel values altered', ii))
            end
        end


        function negativeValuesSurvive(obj)
            % The key test for real() vs abs(). High-pass filtered data are zero
            % mean, so roughly half the pixels are negative. abs() would rectify
            % them and this test would fail.
            im = obj.refImage - mean(obj.refImage(:));
            obj.assumeLessThan(min(im(:)), 0, 'Test image should contain negatives')

            stack = obj.makeShiftedStack(im);
            reg = zstack.registration.applyShifts(stack, zstack.registration.findShifts(stack, im));

            obj.verifyLessThan(min(reg(:)), 0, ...
                'All negative pixels were lost, which suggests rectification')

            for ii = 1:size(stack,3)
                obj.verifyEqual(reg(:,:,ii), im, 'AbsTol', 1e-6, ...
                    sprintf('Frame %d was not restored when data were signed', ii))
            end
        end


        function intensityIsNotRescaled(obj)
            % One bright pixel must not change the scale of the whole stack
            im = obj.refImage;
            im(10,10) = 1e6; % A hot pixel in the reference only

            stack = obj.makeShiftedStack(obj.refImage);
            reg = zstack.registration.applyShifts(stack, zstack.registration.findShifts(stack, im));

            obj.verifyEqual(max(reg(:)), max(obj.refImage(:)), 'RelTol', 1e-6, ...
                'A hot pixel in the target changed the scale of the moving data')
        end


        function diffPhaseIsZero(obj)
            % The phase term should be ~0 for real images with a positive
            % correlation peak. If this holds the exp(i*phase) multiplies in
            % applyShifts are no-ops and could be removed.
            stack = obj.makeShiftedStack(obj.refImage);
            coef = zstack.registration.findShifts(stack, obj.refImage);

            for ii = 1:length(coef)
                obj.verifyEqual(coef(ii).diffPhase, 0, 'AbsTol', 1e-9, ...
                    sprintf('diffPhase was not ~0 for frame %d', ii))
            end
        end


        function shiftsAreRecovered(obj)
            % The reported offsets must undo the shifts we applied
            stack = obj.makeShiftedStack(obj.refImage);
            coef = zstack.registration.findShifts(stack, obj.refImage);
            obj.assertNumElements(coef, size(stack,3), 'Expected one set of shifts per frame')

            recovered = cell2mat(arrayfun(@(x) x.OffsetPixel(:)', coef, 'uni', false)');

            % Shifts wrap, so compare modulo the image size
            imSize = [size(obj.refImage,1), size(obj.refImage,2)];
            expected = mod(-obj.shifts, imSize);
            obj.verifyEqual(mod(recovered,imSize), expected, ...
                'Recovered pixel offsets do not undo the applied shifts')
        end



        % findShifts and applyShifts: finding and applying shifts as separate steps

        function applyShiftsWithOneShiftMovesEveryFrame(obj)
            % A single set of shifts is applied to every frame alike
            stack = repmat(obj.refImage, 1, 1, 3);
            oneShift = struct('diffPhase', 0, 'OffsetPixel', [3 -5]);
            reg = zstack.registration.applyShifts(stack, oneShift);
            for ii = 1:3
                obj.verifyEqual(reg(:,:,ii), circshift(obj.refImage, [3 -5]), 'AbsTol', 1e-6, ...
                    sprintf('Frame %d was not shifted by the single set of shifts', ii))
            end
        end

        function findShiftsRejectsWrongSizeReference(obj)
            stack = obj.makeShiftedStack(obj.refImage);
            obj.verifyError(@() zstack.registration.findShifts(stack, obj.refImage(1:10,:)), ...
                'zstack:findShifts:sizeMismatch')
        end

        function findShiftsReturnsStats(obj)
            % The optional stats output keeps the fields apply_ffttrans returned
            stack = obj.makeShiftedStack(obj.refImage);
            [coef, stats] = zstack.registration.findShifts(stack, obj.refImage);
            obj.assertEqual(sort(fieldnames(stats)), ...
                sort({'before'; 'after'; 'routine'; 'params'; 'target'; 'coef'}), ...
                'stats does not have the expected fields')
            obj.verifyEqual(stats.coef, coef)
            obj.verifyEqual(stats.before, double(stack))
            obj.verifyEqual(stats.after, zstack.registration.applyShifts(stack, coef))
            obj.verifyEqual(stats.target, obj.refImage)
            obj.verifyEqual(stats.routine, 'ffttrans')
            obj.verifyEqual(stats.params.usfac, 1)
        end
    end % methods (Test)


end % classdef registration_tests < matlab.unittest.TestCase
