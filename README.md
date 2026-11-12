# scanimage_zstack_tools
Record high quality in vivo z stacks and assemble them using image registration after acquisition

Requires MATLAB R2021a or later and the Image Processing Toolbox.


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


# Producing a z-stack from a slow stack
You have a ScanImage z-stack with several frames per slice, possibly split over several files.
Register and average each slice, then register the slices to one another, with:

```matlab
 zstack.zplanes2tiff(filename, 2, {'red.tiff', 'green.tiff'});
```

Where the second input argument is the channel to use for registration, and the third gives one
output file per saved channel, in the order ScanImage saved them.
Each file's metadata (the acquisition settings, the inputs used and values derived during the run)
is saved twice: in the TIFF's `Software` tag, and as a JSON file of the same name beside it
(`red.json`, `green.json`); see `help zstack.zplanes2stack`.
It also saves `slices.csv` beside the first output: one row per slice, with its z position, the
shift applied to bring it into line with slice 1, the step from the previous slice, and how many of
its frames the within-slice registration left unshifted. Choose another name with
`'sliceFile', 'name.csv'` (or `.tsv` for a tab-separated file), e.g. to save two stacks in one folder.
Each run is logged to `zplanes2tiff_<date>_<time>.log` beside the first output file, ending with a
`Result:` line (SUCCESS, FAILED or ERROR).

To get the registered stack without saving it, use `zstack.zplanes2stack(filename, 2)`.


# Recording a zstack easily in ScanImage
Use the tool `zstack.record`. Instructions: `help zstack.record`
