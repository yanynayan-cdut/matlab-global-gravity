# Geospatial data provenance

Generated UTC: 2026-09-27T14:02:27.984228+00:00

## Sources
- Natural Earth version 5.2.0-pre Admin 0 countries, 1:50m GeoJSON (public domain): https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson
- Natural Earth Populated Places 10m GeoJSON (public domain): https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_populated_places_simple.geojson
- Natural Earth source policy: https://www.naturalearthdata.com/about/terms-of-use/
- mledoze/countries metadata (ISO codes, names, Chinese translations, official capital lists), ODbL; full license is bundled as COUNTRY_METADATA_LICENSE.txt: https://github.com/mledoze/countries
- Metadata source commit c8015eebdd94c533358406b0d709f441389e1f2e dated 2026-09-03T08:44:13Z.
- Tiny-capital override records are geocoded using OpenStreetMap Nominatim; request URLs and raw responses are in nominatim_capitals_raw.json. OSM data is copyright OpenStreetMap contributors, ODbL: https://www.openstreetmap.org/copyright

## Country selection and coordinates
- countries contains a 199-record superset. recommended197Iso3 is 193 UN members plus the Holy See/Vatican City, Palestine, Cook Islands and Niue. Taiwan and Kosovo are present only in the superset pending the user's selection policy.
- The source incorrectly marked Vatican City as a UN member; unMember is corrected to false. Exactly 193 records have unMember=true.
- No country-centroid coordinates are used for capitals. Natural Earth point geometry gives 196 capital locations; OpenStreetMap gives Alofi, Yaren and Ngerulmud. All coordinates are WGS84 geographic longitude/latitude in degrees.
- Special government-seat/multiple-capital cases have notes. One canonical point per record is used for selection and calculator input.
- Boundary lines are Natural Earth 1:50m polygons densified to at most 0.5 degree between vertices, NaN-separated at rings and dateline crossings. Their de facto mapping conventions remain the source's conventions.

## MATLAB schema
- countries: 1x199 struct, fields iso3, iso2, country, countryZh, capital, latitude, longitude, label, search, notes, unMember, source.
- boundaries: 1x242 struct, fields iso3, country, latitude, longitude.
- boundaryLatitude and boundaryLongitude: NaN-separated numeric column vectors for one plot call.
- recommended197Iso3: 1x197 cellstr for explicit selection.

## SHA-256 checksums
- `countries_geojson.json` `3e458fc036ad0a66411f2c1e6cac49c5d7bfb81cb1123bc513b22511a2b7fdeb`
- `populated_places.json` `fd3fa867a320cbd5c5b6bb5bc550afeec2939fb2cef688e508007282a55ac42f`
- `mledoze_countries.json` `99b85dda36895c79caf72e191d035e4b9d82e811ee34f9ca15dfa67d7c561ba8`
- `capital_overrides.json` `4dee4a1d49c3100ee51ebf5f81c58c1a70c40351929aaa873e5789a11477ab4c`
- `nominatim_capitals_raw.json` `8cadc20b7f3700ff07bed28a28c1a463ae0e14e58c217791d278f5fbfcc72316`
- `countries_superset.json` `784608797ad16a91c4fc1c8a3085ea41c0c76baf76e5f8d1e97ec0b63452f757`
- `countries_superset.csv` `1f7462f78164ff337b5984fb679a3f311c931acec97f15ef2db5dd8cfae60180`
- `world_geodata.mat` `dc91ebdf51af596bb9bee5d1d873e461f12929db76c348cc51c8cffec9f72c44`
