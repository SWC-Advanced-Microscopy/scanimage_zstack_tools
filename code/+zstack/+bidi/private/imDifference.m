function [d,im] = imDifference(im_odd, im_even, ff_s, ff_t, offset_rad)
    im_odd  = imToSpatialDomain(im_odd , ff_s, ff_t, offset_rad);
    im_even = imToSpatialDomain(im_even, ff_s, ff_t,-offset_rad);
    d = im_odd - im_even;
    d(isnan(d)) = []; % remove artifacts from interpolation
    d = sum(abs(d(:))) ./ numel(d); % least square difference, normalize by number of elements
    if nargout > 1
        im = cat(3,im_odd,im_even);
        im = permute(im,[1,3,2]);
        im = reshape(im,size(im,1),[]);
    end
end
