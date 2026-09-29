# scanimage_zstack_tools
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
 zstack.io.writeSignedTiff(int16(OUT(1).mean_z),'zstack_red_chan.tiff')
 zstack.io.writeSignedTiff(int16(OUT(2).mean_z),'zstack_green_chan.tiff')
 ```

Note: 1) The need to cast as int16. 2) In this case the first index is red and the second is green. Your data may be different. 
It won't write otherwise and ScanImage writes data as signed ints.


# Recording a zstack easily in ScanImage
Use the tool `zstack.record`. Instructions: `help zstack.record`
