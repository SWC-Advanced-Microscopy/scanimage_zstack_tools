function varargout=apply_ffttrans(movingStack,target,params,targetFFT)
    % Apply an FFT-based translation correction to an image or image time-series
    %
    % function [registered,stats] = zstack.registration.apply_ffttrans(movingStack,target,params)
    %
    % Purpose
    % Apply fft-based translation correction to movingStack (which may be a single
    % image or an image time-series). movingStack is aligned to target.
    %
    % This function is a wrapper which allows us to conduct the fft-based translation
    % correction. It is called recursively when an image stack is supplied, which keeps
    % the registration code neater as it need not be aware of the image stack.
    %
    % Inputs
    % movingStack - A single image or an image time-series which will be aligned
    %               with target.
    % target - The image used as the reference to which to align movingImage. If
    %          target is a coefficients structure produced by this function
    %          (contained in the second output argument) then it applies this to
    %          movingStack.
    % params - structure containing parameter names (structure fields) and parameter
    %          values (structure field values) for the image registration routines.
    %          If not specified, defaults are used. See individual files for the
    %          defaults and possible options. Only parameters the user wants to alter
    %          need to be defined in the structure.
    % targetFFT - [optional, used internally] fft2(target), so that it is computed
    %             once per stack rather than once per frame.
    %
    % Outputs
    % registered - the registered movingStack.
    % stats - the shifts for each frame and other related data.
    %
    %
    % Rob Campbell - August 2012
    %
    % For details on the algorithm:
    % http://www.mathworks.com/matlabcentral/fileexchange/18401


    %----------------------------------------------------------------------
    % Handle default options and parameters
    p.usfac=1; %upsampling factor higher values can produce finer
               %registrations but they also will smear the shot
               %noise. A value of 1 is not sub-pixel and can induce jittering
    p.parallel=false;
    p.verbose=0;

    if nargin>2
        f=fields(params);
        for ii=1:length(f)
            p.(f{ii})=params.(f{ii});
        end
    end

    if p.parallel == true
        p.parallel=tryParallel(p.parallel); %disable parallel execution if there's a problem
    end



    %----------------------------------------------------------------------
    % Call the registration routine recursively if we have an image stack
    if size(movingStack,3)>1

        if p.verbose & ~p.parallel
            zstack.utils.chalk(sprintf('Applying translation correction [%s]',...
                          repmat('.',1,size(movingStack,3))),1)
            fprintf(repmat('\b',1,1+size(movingStack,3)))
        end

        if p.verbose, tic, end

        nFrames=size(movingStack,3);
        registered=ones(size(movingStack));

        % The target image's FFT is the same for every frame, so compute it once
        if isnumeric(target), targetFFT=fft2(target); else, targetFFT=[]; end

        % With 0 workers, parfor runs as an ordinary loop (no toolbox needed).
        % Frames are independent, so the order they run in doesn't matter.
        nWorkers=0;
        if p.parallel, nWorkers=Inf; end

        parfor (ii=1:nFrames, nWorkers)
            if isstruct(target) && ~isscalar(target)
                frameTarget=target(ii); % one set of shifts per frame
            else
                frameTarget=target;     % an image, or one set of shifts for every frame
            end
            [registered(:,:,ii),out(ii)]=...
                zstack.registration.apply_ffttrans(movingStack(:,:,ii),frameTarget,p,targetFFT);
        end

        % Match the class of the "before" data to that of the registered output.
        % No re-scaling is done: a translation preserves pixel values, so the
        % registered stack is already on the same scale as the input.
        movingStack = cast(movingStack,class(registered));

        %Handle the output arguments
        if nargout>0, varargout{1}=registered; end

        if nargout>1
            tmp.before=movingStack;
            tmp.after=registered;
            tmp.routine=regexprep(mfilename,'apply_','');
            tmp.params=p;
            if isnumeric(target), tmp.target=target; end
            tmp.coef=[out.coef];
            varargout{2}=tmp;
        end

        if p.verbose & ~p.parallel
            fprintf('\t %2.2f s\n',toc)
        elseif p.verbose
            fprintf('Applied translation correction to %d frames\n',...
                    size(movingStack,3))
        end

        return
    end



    %----------------------------------------------------------------------
    % Conduct the registration
    %
    % If target is an image of the same size, find the shift that aligns
    % movingStack to it. If target is a set of coefficients, use the shift it
    % holds. Either way, then apply the shift.
    if p.verbose & ~p.parallel, fprintf('*'), end

    if isnumeric(target)
        if any(size(movingStack)-size(target))
            fprintf('Failed to register moving image to target image\n\n\n')
            return
        end
        if nargin<4 || isempty(targetFFT), targetFFT=fft2(target); end
        output=dftregistration(targetFFT,fft2(movingStack),p.usfac);
        OffsetPixel=output([3,4]);
        phase=output(2);
    else
        OffsetPixel=target.OffsetPixel;
        phase=target.diffPhase;
    end

    registered=shiftFrame(movingStack,OffsetPixel,phase);



    %----------------------------------------------------------------------
    % Handle the output arguments
    if nargout>0
        varargout{1}=registered;
    end

    if nargout>1
        out.coef.diffPhase=phase;
        out.coef.OffsetPixel=OffsetPixel;
        out.params=p;
        varargout{2}=out;
    end

end % apply_ffttrans


function registered=shiftFrame(frame,OffsetPixel,phase)
    % Translate one frame by OffsetPixel ([row column]) and apply the phase term
    %
    % For whole-pixel shifts (usfac = 1) the Fourier phase ramp is exactly a
    % circular shift, and taking the real part reduces the phase term to
    % cos(phase) (in practice phase is 0 for real images, so this is 1).
    % Sub-pixel shifts (usfac > 1) still need the Fourier route.
    if all(OffsetPixel==round(OffsetPixel))
        registered=cos(phase)*circshift(double(frame),OffsetPixel);
        return
    end

    [nr,nc]=size(frame);
    Nr = ifftshift([-fix(nr/2):ceil(nr/2)-1]);
    Nc = ifftshift([-fix(nc/2):ceil(nc/2)-1]);
    [Nc,Nr] = meshgrid(Nc,Nr);
    registered=fft2(frame).*exp(i*2*pi*(-OffsetPixel(1)*Nr/nr-OffsetPixel(2)*Nc/nc));
    registered=registered.*exp(-i*phase);
    % real() not abs(): the inverse transform of a translated real image is
    % real bar numerical residue, whereas abs() would rectify any genuinely
    % negative pixels (ScanImage data are signed).
    registered=real(ifft2(registered));

end % shiftFrame
