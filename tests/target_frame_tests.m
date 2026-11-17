classdef target_frame_tests < matlab.unittest.TestCase
    % Tests associated with building the target frame and registering a plane
    %
    % Purpose
    % register_plane registers each frame to a target built by
    % averageCorrelatedFrames, optionally finding the shifts on a blurred copy
    % (sigma) and refining against the mean of the registered frames (refine).
    % Most tests use a synthetic plane in which most frames are still and a few
    % are circularly shifted by known whole-pixel amounts. The target should then
    % be built from the still frames, every moved frame should come back to the
    % reference position, and the returned frames should never be blurred.

    properties
        refImage = [];                  % The underlying (noise-free) image
        nFrames = 30;                   % Frames in the synthetic plane
        movedFrames = [3, 11, 17, 24];  % Frames that are shifted...
        shifts = [ 3, -5; ...
                  -7, 11; ...
                   2,  2; ...
                  12,  8];              % ...by these row/column amounts
        noiseSD = 10;                   % Noise added to every frame
    end % properties


    methods(TestClassSetup)
        function buildReferenceImage(obj)
            % A smooth, structured image so the correlation peak is unambiguous
            [X,Y] = meshgrid(linspace(-3,3,128), linspace(-3,3,96)); % non-square on purpose
            obj.refImage = 1000 * exp(-(X.^2 + Y.^2)) + ...
                            200 * sin(2*pi*X) .* cos(2*pi*Y);
        end
    end




    methods

        function stack = makePlane(obj, amplitude, noiseSD)
            % Noisy copies of the reference image, with the frames in
            % movedFrames circularly shifted by obj.shifts
            rng(42)
            stack = zeros([size(obj.refImage), obj.nFrames]);
            for ii = 1:obj.nFrames
                stack(:,:,ii) = amplitude * obj.refImage + noiseSD * randn(size(obj.refImage));
            end
            for ii = 1:length(obj.movedFrames)
                f = obj.movedFrames(ii);
                stack(:,:,f) = circshift(stack(:,:,f), obj.shifts(ii,:));
            end
        end

        function expected = expectedOffsets(obj)
            % Still frames need no shift; moved frames need the opposite of theirs
            expected = zeros(obj.nFrames, 2);
            expected(obj.movedFrames,:) = -obj.shifts;
        end

    end % methods


    methods(Static)

        function offsets = recoveredOffsets(reg_params)
            % The [row col] offset of each frame
            offsets = cell2mat(arrayfun(@(x) x.OffsetPixel(:)', reg_params.coef, 'uni', false)');
        end

    end % methods(Static)




    methods (Test)

        % averageCorrelatedFrames

        function targetIsBuiltFromStillFrames(obj)
            % The moved frames correlate poorly with the rest, so they should be
            % left out. The target is then the reference plus averaged noise only.
            stack = obj.makePlane(1, obj.noiseSD);
            target = zstack.registration.averageCorrelatedFrames(stack);

            obj.verifySize(target, size(obj.refImage))
            obj.verifyLessThan(std(target(:) - obj.refImage(:)), 2 * obj.noiseSD / sqrt(21), ...
                'The target differs from the reference by more than noise, so a moved frame was probably included')
        end


        function usingAllFramesGivesThePlainMean(obj)
            % With nCor = nFrames - 1 every frame is used exactly once
            stack = obj.makePlane(1, obj.noiseSD);
            target = zstack.registration.averageCorrelatedFrames(stack, obj.nFrames - 1);

            obj.verifyEqual(target, mean(stack,3), 'AbsTol', 1e-9, ...
                'Using every frame did not give the plain mean')
        end


        function fewerFramesThanNCor(obj)
            % A slice may have fewer than nCor + 1 frames. Each frame should then
            % be used once, giving the plain mean.
            stack = obj.makePlane(1, obj.noiseSD);
            stack = stack(:,:,1:10);
            target = zstack.registration.averageCorrelatedFrames(stack);

            obj.verifyEqual(target, mean(stack,3), 'AbsTol', 1e-9, ...
                'With fewer frames than nCor, some frames were counted more than once')
        end


        % register_plane

        function shiftsAreRecovered(obj)
            % Each combination of refine and sigma must undo the applied shifts
            stack = obj.makePlane(1, obj.noiseSD);
            imSize = size(obj.refImage);
            settings = [false 0; true 0; false 2; true 2]; % [refine sigma]

            for ii = 1:size(settings,1)
                [~, reg_params] = zstack.registration.register_plane(stack, settings(ii,1), settings(ii,2));
                obj.verifyEqual(mod(obj.recoveredOffsets(reg_params), imSize), ...
                                mod(obj.expectedOffsets(), imSize), ...
                    sprintf('Wrong offsets with refine = %d, sigma = %d', settings(ii,1), settings(ii,2)))
            end
        end


        function movedFramesAreRestored(obj)
            % Without noise the still frames are identical, so each moved frame
            % must come back exactly equal to the reference image
            stack = obj.makePlane(1, 0);
            reg = zstack.registration.register_plane(stack, true, 2);

            for f = obj.movedFrames
                obj.verifyEqual(reg(:,:,f), obj.refImage, 'AbsTol', 1e-6, ...
                    sprintf('Frame %d was not restored to the reference image', f))
            end
        end


        function outputIsNotBlurred(obj)
            % Shifts are found on a blurred copy but applied to the original
            % frames. A whole-pixel shift permutes pixels, so each returned frame
            % must hold exactly the values of the corresponding input frame.
            stack = obj.makePlane(1, obj.noiseSD);
            reg = zstack.registration.register_plane(stack, false, 2);

            for ii = 1:obj.nFrames
                obj.verifyEqual(sort(reshape(reg(:,:,ii),[],1)), ...
                                sort(reshape(stack(:,:,ii),[],1)), 'AbsTol', 1e-6, ...
                    sprintf('Frame %d had its pixel values altered (blurred?)', ii))
            end
        end


        function blurUnsticksDimData(obj)
            % Regression test for registration stuck at zero in dim slices. With
            % 21 frames and nCor = 20 every frame is part of its own target, and
            % when the structure is weak against pixel noise each frame's own
            % noise pins its shift at zero. Blurring should recover the shifts:
            % afterwards every frame should be within 1px of the common
            % position.
            rng(7)
            nDim = 21;
            trueShifts = randi([-4 4], nDim, 2);
            stack = zeros([size(obj.refImage), nDim]);
            for ii = 1:nDim
                frame = 0.02 * obj.refImage + 20 * randn(size(obj.refImage)); % dim and noisy
                stack(:,:,ii) = circshift(frame, trueShifts(ii,:));
            end

            [~, plain] = zstack.registration.register_plane(stack);
            [~, blurred] = zstack.registration.register_plane(stack, false, 2);

            % Error of each frame from the common position (the target's own
            % position is arbitrary, so measure from the median)
            errPlain = obj.recoveredOffsets(plain) + trueShifts;
            errPlain = errPlain - median(errPlain);
            errBlurred = obj.recoveredOffsets(blurred) + trueShifts;
            errBlurred = errBlurred - median(errBlurred);

            % Check the data reproduce the problem: without the blur, frames
            % should be far from the common position
            obj.assumeGreaterThan(max(abs(errPlain(:))), 2, ...
                'The test data do not reproduce registration stuck at zero')

            obj.verifyLessThanOrEqual(max(abs(errBlurred(:))), 1, ...
                'Frames were more than 1 px from the common position after blurring')
        end

    end % methods (Test)


end % classdef target_frame_tests < matlab.unittest.TestCase