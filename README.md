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

Note: 
1. The need to cast as int16. ScanImage writes as signed ints.
2. In this case the first index is the red channel and the second is the green channel. This is rig-dependent and yours could be the other way around or you may even have more than two channels. 

# Producing a z-stack from a slow stack
You have a ScanImage z-stack with several frames per slice, possibly split over several files.
Register and average each slice, then register the slices to one another, with:

```matlab
 zstack.zplanes2tiff(filename, 2, {'red.tiff', 'green.tiff'});
```

Where the second input argument is the channel to use for registration, and the third gives one
output file per saved channel, in the order ScanImage saved them.
Each file's `Software` tag holds the acquisition settings, the inputs used and values derived
during the run; see `help zstack.zplanes2stack`.
To get the registered stack without saving it, use `zstack.zplanes2stack(filename, 2)`.
Each run is logged to `zplanes2tiff_<date>_<time>.log` beside the first output file, ending with a
`Result:` line (SUCCESS, FAILED or ERROR).


# Recording a zstack easily in ScanImage
Use the tool `zstack.record`. Instructions: `help zstack.record`
