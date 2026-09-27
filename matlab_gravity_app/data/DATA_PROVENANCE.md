# Geospatial data provenance

Generated UTC: 2026-09-27T13:59:55.883273Z

## Sources
- Natural Earth Admin 0 countries, 1:50m GeoJSON: https://github.com/nvkelso/natural-earth-vector (public domain).
- Natural Earth Populated Places 10m GeoJSON (capital points): https://github.com/nvkelso/natural-earth-vector (public domain).
- mledoze/countries metadata (ISO codes, names, Chinese translations, official capital lists): https://github.com/mledoze/countries (Open Database License).
- Tiny-capital override records are geocoded using OpenStreetMap Nominatim; request URLs and raw responses are in `nominatim_capitals_raw.json`. OSM data is © OpenStreetMap contributors under the ODbL.
- Canonical set in `world_geodata.mat`: 193 UN members + Palestine + Cook Islands + Niue (197 rows). `recommended197Iso3` makes the policy explicit. The `countries` table includes two additional reference records (Kosovo and Taiwan) for search and map matching.
- Boundary lines are Natural Earth 1:50m polygons densified to ≤0.5° between vertices, NaN-separated at rings and dateline crossings.

## SHA-256 checksums
- `countries_geojson.json` `3e458fc036ad0a66411f2c1e6cac49c5d7bfb81cb1123bc513b22511a2b7fdeb`
- `populated_places.json` `fd3fa867a320cbd5c5b6bb5bc550afeec2939fb2cef688e508007282a55ac42f`
- `mledoze_countries.json` `99b85dda36895c79caf72e191d035e4b9d82e811ee34f9ca15dfa67d7c561ba8`
- `capital_overrides.json` `4dee4a1d49c3100ee51ebf5f81c58c1a70c40351929aaa873e5789a11477ab4c`
- `nominatim_capitals_raw.json` `8cadc20b7f3700ff07bed28a28c1a463ae0e14e58c217791d278f5fbfcc72316`
- `countries_superset.json` `784608797ad16a91c4fc1c8a3085ea41c0c76baf76e5f8d1e97ec0b63452f757`
- `countries_superset.csv` `1f7462f78164ff337b5984fb679a3f311c931acec97f15ef2db5dd8cfae60180`
- `world_geodata.mat` `9818e0e3e62cf2093b7b44b2ba4521a483c97df9c511386efec8becc5d776355`
