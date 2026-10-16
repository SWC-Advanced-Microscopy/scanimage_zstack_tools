classdef bidi_tests < matlab.unittest.TestCase
    % Tests associated with bidirectional scanning correction
    %
    % Purpose
    % zstack.bidi.getShift estimates how far the even lines of a frame must be
    % shifted so that they line up with the odd lines. We build a frame with no
    % line offset, shift its even lines by a known whole-pixel amount, and check
    % that getShift returns the shift that undoes it. zplanes2stack relies on a
    % sign convention when it applies the shift, which this test covers.
    % 
    % The scanner metadata are typical values for a resonant scanner, not
    % values read from a real header. linePhase only offsets the reported
    % phase; it does not affect the estimated shift.

    properties
        refImage = [];  % A frame with no line offset
        metadata = struct('linePhase', -2e-6, ...
                          'fillFractionSpatial', 0.9, ...
                          'fillFractionTemporal', 0.712867, ...
                          'scannerFrequency', 7910);
        combShifts = [-4, -1, 1, 3, 6];  % Offsets applied to the even lines
    end % properties


    methods(TestClassSetup)
        function buildReferenceImage(obj)
            % Structure along X to measure the offset, varying slowly along Y so
            % that neighbouring odd and even lines match
            rng(42)
            [X,Y] = meshgrid(linspace(-3,3,256), linspace(-3,3,128));
            obj.refImage = 1000 * exp(-(X.^2 + Y.^2)) + ...
                            200 * sin(4*pi*X) .* cos(pi*Y/3) + ...
                              5 * randn(size(X));
        end
    end




    methods

        function im = addComb(~, im, s)
            % Shift the even lines by s pixels, as a line-phase error would.
            % The same operation as +bidi/private/shiftEvenLines.
            im(2:2:end,:) = circshift(im(2:2:end,:), [0, s]);
        end

    end % methods




    methods (Test)

        function noCombNeedsNoShift(obj)
            % getShift reports NaN if the phase already matches exactly, or 0 if
            % its search settles at no shift. Either means "no correction".
            [~, stats] = zstack.bidi.getShift(obj.refImage, obj.metadata, false, true);

            obj.verifyTrue(isnan(stats.shiftAmnt) || stats.shiftAmnt == 0, ...
                sprintf('A frame with no line offset gave a shift of %d', stats.shiftAmnt))
        end


        function combIsRecovered(obj)
            % The returned shift must undo the applied offset, in both directions
            for s = obj.combShifts
                [~, stats] = zstack.bidi.getShift(obj.addComb(obj.refImage, s), obj.metadata, false, true);
                obj.verifyEqual(stats.shiftAmnt, -s, ...
                    sprintf('Even lines offset by %d px, but getShift returned %d', s, stats.shiftAmnt))
            end
        end


        function correctedFrameMatchesOriginal(obj)
            % Shifting even lines is lossless, so the corrected frame must be
            % exactly the frame before the offset was added
            s = 3;
            [corrected, stats] = zstack.bidi.getShift(obj.addComb(obj.refImage, s), obj.metadata, false, true);
            obj.assumeEqual(stats.shiftAmnt, -s, 'Shift not recovered; see combIsRecovered')

            obj.verifyEqual(corrected, obj.refImage, 'AbsTol', 1e-9, ...
                'The corrected frame does not match the frame without an offset')
        end


        function offsetBeyondSearchRangeFails(obj)
            % getShift tests at most maxIter - 1 = 9 px. A larger offset should
            % be reported as a failure (NaN), not as a wrong shift.
            [~, stats] = zstack.bidi.getShift(obj.addComb(obj.refImage, 15), obj.metadata, false, true);

            obj.verifyTrue(isnan(stats.shiftAmnt), ...
                sprintf('A 15 px offset returned a shift of %d instead of NaN', stats.shiftAmnt))
        end

    end % methods (Test)


end % classdef bidi_tests < matlab.unittest.TestCase