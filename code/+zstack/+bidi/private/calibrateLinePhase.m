function newPhase = calibrateLinePhase(im, metaData)

    linePhase = metaData.linePhase;
    ff_s = metaData.fillFractionSpatial;
    ff_t = metaData.fillFractionTemporal;
    scannerFrequency = metaData.scannerFrequency;

    tf = 0;
    if ~tf
        imT = imToTimeDomain(im,ff_s,ff_t);
    else
        imT = im;
    end

    im_odd  = imT(:,1:2:end);
    im_even = imT(:,2:2:end);

    % first brute force search to find minimum
    offsets_rad = linspace(-1,1,31)*pi/8;
    ds = arrayfun(@(offset_rad)imDifference(im_odd,im_even,ff_s,ff_t,offset_rad),offsets_rad);
    [d,idx] = min(ds);
    offset_rad = offsets_rad(idx);

    % secondary brute force search to refine minimum
    offsets_rad = offset_rad+linspace(-1,1,51)*diff(offsets_rad(1:2));
    ds = arrayfun(@(offset_rad)imDifference(im_odd,im_even,ff_s,ff_t,offset_rad),offsets_rad);
    [d,idx] = min(ds);
    offset_rad = offsets_rad(idx);

    offsetLinePhase = offset_rad /(2*pi)/scannerFrequency;
    linePhase =  linePhase - offsetLinePhase;

    newPhase = linePhase;

end
