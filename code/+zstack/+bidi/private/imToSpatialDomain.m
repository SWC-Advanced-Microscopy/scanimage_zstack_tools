function im = imToSpatialDomain(im,ff_s,ff_t,offset_rad)
    nPix = size(im,1);
    xx_rad = linspace(-ff_t,ff_t,nPix)*pi/2+offset_rad;
    xx_lin = linspace(-ff_s,ff_s,nPix);
    xx_radq = asin(xx_lin);

    im = interp1(xx_rad,im,xx_radq,'linear',NaN);
end
