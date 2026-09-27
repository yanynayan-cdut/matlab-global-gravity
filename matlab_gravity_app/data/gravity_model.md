# EGM2008 gravity data and calculation

The app uses coefficients from the official ICGEM distribution of **EGM2008**,
an Earth gravity model estimated from satellite, terrestrial, airborne and
satellite-altimetry observations. It does not label every displayed value as
a direct gravimeter reading. No generated or sinusoidal substitute field is
used.

Source: https://icgem.gfz-potsdam.de/tom_longtime

Model reference: Pavlis, N. K., Holmes, S. A., Kenyon, S. C., and Factor, J. K.
(2012), *The development and evaluation of the Earth Gravitational Model 2008
(EGM2008)*, Journal of Geophysical Research: Solid Earth, 117, B04406,
doi:10.1029/2011JB008916.

The bundled coefficient file is an exact subset through degree and order 180
of the original source (maximum degree 2190). Truncation limits the shortest
represented half wavelength to approximately 111 km. The grid is sampled
every 1 degree; it cannot resolve site geology, buildings or local terrain.
The original archive hash, download address and grid ranges are recorded in
`gravity_provenance.json`.

## Definitions and units

- `lat` and `lon`: WGS84 geodetic angles in degrees.
- Grid dimensions: 181 latitude rows (-90 to +90) by 361 longitude columns
  (-180 to +180, including the repeated seam).
- `g`: magnitude of gravitational **plus centrifugal** acceleration, m/s².
- `disturbance`: `g - normalGravity`, m/s²; multiply by 100000 for mGal.
- `normalGravity`: WGS84 Somigliana normal gravity on the ellipsoid, m/s².
- Grid height: WGS84 **ellipsoidal** height `h = 0 m`, which is not the geoid
  surface and is not the terrain surface.

`gravity_at_location(latitude,longitude,height)` accepts ellipsoidal height
in metres and evaluates the spherical harmonics at that exact coordinate.
For an altitude above mean sea level H, `h = H + N`, where N is the geoid
undulation. If the UI substitutes H for h, it explicitly states the
approximation; it does not claim an exact height conversion.

## Gravity synthesis

The gravitational potential is

`V = GM/r * sum_n (R/r)^n * sum_m Pnm(sin(phi)) * (Cnm*cos(m*lambda) + Snm*sin(m*lambda))`.

Here r and phi are geocentric radius and latitude calculated from the WGS84
geodetic input. The Pnm are fully normalized (4-pi normalization, without the
Condon-Shortley phase). GM and R are read from the EGM2008 header:
`GM = 3.986004415e14 m³/s²`, `R = 6378136.3 m`.

The three spherical components are the analytical derivatives of V, with
the centrifugal potential `0.5 * omega² * r² * cos(phi)²` included. The app
reports the Euclidean norm of those three components, with
`omega = 7.292115e-5 rad/s`. It does not use only the radial component.

At nonzero height the diagnostic normal gravity value uses the second-order
WGS84 height continuation. This affects the diagnostic disturbance, not the
full model gravity used to calculate the force `G = mass * g`.

## Rebuilding and verification

Run `python scripts/rebuild_gravity_data.py` from the project folder to
download the official model, verify its SHA-256 digest, preserve the exact
coefficient subset and rebuild `gravity_grid.mat`. NumPy and SciPy are only
developer dependencies; the MATLAB app reads the bundled `.mat` data without
Python or additional MATLAB toolboxes.

The one-degree display and its exaggerated radial relief are a visual
encoding of gravity. They are not a 3D model of Earth's real topography or
its geoid shape. Coefficient values are not modified to exaggerate relief.
