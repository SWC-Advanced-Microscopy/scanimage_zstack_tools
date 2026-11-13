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

        function findShiftsRejectsWrongSizeTarget(obj)
            stack = obj.makeShiftedStack(obj.refImage);
            obj.verifyError(@() zstack.registration.findShifts(stack, obj.refImage(1:10,:)), ...
                'zstack:findShifts:sizeMismatch')
        end

    end % methods (Test)


end % classdef registration_tests < matlab.unittest.TestCase
