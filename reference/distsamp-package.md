# distsamp: Segment Aerial Line-Transect Survey Data for Distance Sampling

Turns marine mammal aerial line-transect survey data recorded in the
North Atlantic Right Whale Consortium (NARWC) sightings database format
into effort segments and detection distances, ready for distance
sampling and density surface modeling. Reading and standardising an
extract is done by the 'narwcr' package, which this one shares with
other analyses of the same archive; what follows is specific to distance
sampling. Accumulates great-circle effort, splits survey lines at breaks
in effort, and chops continuous tracklines into segments of a target
length following the approach of Becker et al. (2010)
[doi:10.3354/meps08696](https://doi.org/10.3354/meps08696) , within the
segmented line-transect framework of Hedley and Buckland (2004)
[doi:10.1198/1085711043578](https://doi.org/10.1198/1085711043578) and
Miller et al. (2013)
[doi:10.1111/2041-210X.12105](https://doi.org/10.1111/2041-210X.12105) .
Resolves right-angle distances from every source the archive records,
whether declination angles, the two 'STRIP' interval code books, exact
sighting positions, or a break-off to circle, recording which supplied
each detection; and assembles them into the flatfile that 'Distance'
accepts.

## References

The segmentation method:

Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C.,
Barlow, J. and Redfern, J.V. (2010) Comparing California Current
cetacean-habitat models developed using in situ and remotely sensed sea
surface temperature data. *Marine Ecology Progress Series* 413:163-183.
[doi:10.3354/meps08696](https://doi.org/10.3354/meps08696)

The statistical framework it serves:

Hedley, S.L. and Buckland, S.T. (2004) Spatial models for line transect
sampling. *Journal of Agricultural, Biological, and Environmental
Statistics* 9:181-199.
[doi:10.1198/1085711043578](https://doi.org/10.1198/1085711043578)

Miller, D.L., Burt, M.L., Rexstad, E.A. and Thomas, L. (2013) Spatial
models for distance sampling data: recent developments and future
directions. *Methods in Ecology and Evolution* 4:1001-1010.
[doi:10.1111/2041-210X.12105](https://doi.org/10.1111/2041-210X.12105)

Buckland, S.T., Anderson, D.R., Burnham, K.P., Laake, J.L., Borchers,
D.L. and Thomas, L. (2001) *Introduction to Distance Sampling:
Estimating Abundance of Biological Populations.* Oxford University
Press, New York, NY.

The data format and survey protocol:

Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database:
A Guide for Users and Contributors, Version 8*. NARWC Reference Document
2023-01. University of Rhode Island, Graduate School of Oceanography,
Narragansett, RI.

CETAP (1982) *A Characterization of Marine Mammals and Turtles in the
Mid- and North-Atlantic Areas of the U.S. Outer Continental Shelf, Final
Report.* Cetacean and Turtle Assessment Program, University of Rhode
Island. Bureau of Land Management, Washington, DC.

Kenney, R.D. and Winn, H.E. (1986) Cetacean high-use habitats of the
northeast United States continental shelf. *Fishery Bulletin*
84(2):345-357.

A full list, with what each source is relied on for, is in
`docs/06-references.md` in the package repository.

## See also

Useful links:

- <https://github.com/chross22/distsamp>

- Report bugs at <https://github.com/chross22/distsamp/issues>

## Author

**Maintainer**: Camille Ross <camille.ross@maine.edu>
([ORCID](https://orcid.org/0000-0002-1428-2294))

Authors:

- Camille Ross <camille.ross@maine.edu>
  ([ORCID](https://orcid.org/0000-0002-1428-2294))
