function coef=findShifts(movingStack,target,params)
    % Find the shift that aligns each frame of an image stack with a target image
    %
    % function coef = zstack.registration.findShifts(movingStack,target,params)
    %
    % Purpose
    % Uses FFT-based cross-correlation to find, for each frame of movingStack, the
    % translation that aligns it with target. Apply the shifts to this stack, or
    % to another channel, with zstack.registration.applyShifts.
    %
    % Inputs
    % movingStack - a single image or an image stack (rows x columns x frames).
    % target - the image to align each frame with; the same size as one frame.
    % params - [optional] structure of parameters. Only those to change from the
    %          defaults need be given:
    %          usfac - upsampling factor. 1 (default) finds whole-pixel shifts.
    %                  Higher values find finer shifts but also smear the shot
    %                  noise.
    %          parallel - find the shifts of different frames in parallel (needs
    %                     the Parallel Computing Toolbox). Default: false.
    %          verbose - report the time taken. Default: false.
    %
    % Outputs
    % coef - structure array, one element per frame, with fields:
    %        diffPhase - global phase difference (0 for real images in practice).
    %        OffsetPixel - [row column] shift that aligns the frame with target.
    %
    %
    % For details on the algorithm:
    % http://www.mathworks.com/matlabcentral/fileexchange/18401


    % Default parameters, overridden by any given in params
    p.usfac=1;
    p.parallel=false;
    p.verbose=false;

    if nargin>2
        f=fields(params);
        for ii=1:length(f)
            p.(f{ii})=params.(f{ii});
        end
    end

    if p.parallel
        p.parallel=tryParallel(p.parallel); % disable parallel execution if there's a problem
    end

    if ~isequal(size(target),[size(movingStack,1),size(movingStack,2)])
        error('zstack:findShifts:sizeMismatch', ...
            'The target image (%s) must be the same size as each frame (%s)', ...
            mat2str(size(target)), mat2str([size(movingStack,1),size(movingStack,2)]))
    end

    if p.verbose, tic, end

    % The target image's FFT is the same for every frame, so compute it once
    targetFFT=fft2(target);

    % With 0 workers, parfor runs as an ordinary loop (no toolbox needed).
    % Frames are independent, so the order they run in doesn't matter.
    nFrames=size(movingStack,3);
    nWorkers=0;
    if p.parallel, nWorkers=Inf; end
    usfac=p.usfac;

    parfor (ii=1:nFrames, nWorkers)
        output=dftregistration(targetFFT,fft2(movingStack(:,:,ii)),usfac);
        coef(ii)=struct('diffPhase',output(2),'OffsetPixel',output([3,4]));
    end

    if p.verbose
        fprintf('Found shifts for %d frames in %0.2f s\n',nFrames,toc)
    end

end % findShifts
