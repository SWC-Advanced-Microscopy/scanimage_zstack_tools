# scanimage_ztack_tools
Record high quality in vivo z stacks and assemble them using image registration after acquisition


# Producing a z-stack from time series data
You have a time series of functional data with data obtained from multiple planes. 
From this you want to produce a z-stack. 
Run:

```matlab
 OUT=zstack.timeseries2zplanes(filename,1);
```

Where the second input argument is the channel to use for registration. 
If the dataset has more than one channel, the remaining channels are registered using coefficients calculated from the named channel. 
To save data there is currently no elegant writer function, just do:


```matlab
 zstack.io.writeSignedTiff(int16(OUT(1).mean_z),'zstack_chan_01.tiff',
 zstack.io.writeSignedTiff(int16(OUT(2).mean_z),'zstack_chan_02.tiff',
 ```

If the image data are all positive you can cast as `uinit16` instead. 
The above will write data to the tiff as either `int16` or `uint16`. 
We retain this flexibility because ScanImage writes data as signed ints and we may not have removed the baseline at this point. 
