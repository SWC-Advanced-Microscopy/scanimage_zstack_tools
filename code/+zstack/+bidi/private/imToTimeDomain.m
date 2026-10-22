function im = imToTimeDomain(im,ff_s,ff_t)
    nPix = size(im,1);
    xx_lin = linspace(-ff_s,ff_s,nPix);
    xx_rad = linspace(-ff_t,ff_t,nPix)*pi/2;
    xx_linq = sin(xx_rad);

    im = interp1(xx_lin,im,xx_linq,'linear',NaN);
end
