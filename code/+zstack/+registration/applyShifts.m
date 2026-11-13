function registered=applyShifts(movingStack,coef,params)
    % Translate each frame of an image stack by a given shift
    %
    % function registered = zstack.registration.applyShifts(movingStack,coef,params)
    %
    % Purpose
    % Applies shifts found by zstack.registration.findShifts, either to the stack
    % they were found on or to another channel recorded alongside it, so that all
    % channels stay in register with one another.
    %
    % Inputs
    % movingStack - a single image or an image stack (rows x columns x frames).
    % coef - shifts from zstack.registration.findShifts: one element per frame, or
    %        a single element applied to every frame.
    % params - [optional] structure of parameters. Only those to change from the
    %          defaults need be given:
    %          parallel - shift different frames in parallel (needs the Parallel
    %                     Computing Toolbox). Default: false.
    %          verbose - report the time taken. Default: false.
    %
    % Outputs
    % registered - the translated stack, as double. Pixel values are not rescaled:
    %              a translation preserves them.


    % Default parameters, overridden by any given in params
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

    if p.verbose, tic, end

    % With 0 workers, parfor runs as an ordinary loop (no toolbox needed).
    % Frames are independent, so the order they run in doesn't matter.
    nFrames=size(movingStack,3);
    nWorkers=0;
    if p.parallel, nWorkers=Inf; end

    registered=zeros(size(movingStack));
    parfor (ii=1:nFrames, nWorkers)
        if isscalar(coef)
            frameCoef=coef;     % one set of shifts for every frame
        else
            frameCoef=coef(ii); % one set of shifts per frame
        end
        registered(:,:,ii)=shiftFrame(movingStack(:,:,ii),frameCoef.OffsetPixel,frameCoef.diffPhase);
    end

    if p.verbose
        fprintf('Applied shifts to %d frames in %0.2f s\n',nFrames,toc)
    end

end % applyShifts


function registered=shiftFrame(frame,OffsetPixel,phase)
    % Translate one frame by OffsetPixel ([row column]) and apply the phase term
    %
    % For whole-pixel shifts (usfac = 1) the Fourier phase ramp below is exactly a
    % circular shift, and taking the real part reduces the phase term to
    % cos(phase) (in practice phase is 0 for real images, so this is 1).
    if all(OffsetPixel==round(OffsetPixel))
        registered=cos(phase)*circshift(double(frame),OffsetPixel);
        return
    end

    row_shift=OffsetPixel(1);
    col_shift=OffsetPixel(2);

    frameFFT=fft2(frame);

    [nr,nc,~]=size(frame);
    Nr = ifftshift([-fix(nr/2):ceil(nr/2)-1]);
    Nc = ifftshift([-fix(nc/2):ceil(nc/2)-1]);
    [Nc,Nr] = meshgrid(Nc,Nr);

    registered=frameFFT.*exp(i*2*pi*(-row_shift*Nr/nr-col_shift*Nc/nc));
    registered=registered.*exp(-i*phase);
    % real() not abs(): the inverse transform of a translated real image
    % is real bar numerical residue, whereas abs() would rectify any
    % genuinely negative pixels (ScanImage data are signed).
    registered=real(ifft2(registered));

end % shiftFrame
