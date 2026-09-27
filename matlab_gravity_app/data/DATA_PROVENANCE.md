# Geospatial data provenance

Generated UTC: 2026-09-27T14:09:31.036741+00:00

## Sources
- Natural Earth version 5.2.0-pre Admin 0 countries, 1:50m GeoJSON (public domain): https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson
- Natural Earth Populated Places 10m GeoJSON (public domain): https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_populated_places_simple.geojson
- Natural Earth full Populated Places 10m GeoJSON, NAME_ZH (Chinese capital aliases): https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_populated_places.geojson
- Natural Earth source policy: https://www.naturalearthdata.com/about/terms-of-use/
- mledoze/countries metadata (ISO codes, names, Chinese translations, official capital lists), ODbL; full license is bundled as COUNTRY_METADATA_LICENSE.txt: https://github.com/mledoze/countries
- Metadata source commit c8015eebdd94c533358406b0d709f441389e1f2e dated 2026-09-03T08:44:13Z.
- Tiny-capital override records are geocoded using OpenStreetMap Nominatim; request URLs and raw responses are in nominatim_capitals_raw.json. OSM data is copyright OpenStreetMap contributors, ODbL: https://www.openstreetmap.org/copyright

## Country selection and coordinates
- countries contains a 199-record superset. recommended197Iso3 is 193 UN members plus the Holy See/Vatican City, Palestine, Cook Islands and Niue. This 197-record selection was approved on 2026-09-27 and is the application default (`CountrySet='un197'`); no startup confirmation is required. Taiwan and Kosovo are present only in the superset for explicitly supplied custom selections.
- The source incorrectly marked Vatican City as a UN member; unMember is corrected to false. Exactly 193 records have unMember=true.
- No country-centroid coordinates are used for capitals. Natural Earth point geometry gives 196 capital locations; OpenStreetMap gives Alofi, Yaren and Ngerulmud. All coordinates are WGS84 geographic longitude/latitude in degrees.
- Special government-seat/multiple-capital cases have notes. One canonical point per record is used for selection and calculator input.
- All 199 records have Chinese capital aliases: 197 from Natural Earth NAME_ZH matched by NE_ID (or exact city name for Alofi); 2 from OSM name:zh-Hans (Yaren/Ngerulmud), raw responses in nominatim_capital_names_raw.json.
- Boundary lines are Natural Earth 1:50m polygons densified to at most 0.5 degree between vertices, NaN-separated at rings and dateline crossings. Their de facto mapping conventions remain the source's conventions.
- Every recommended 197 record has a matching boundary feature. 242 polygon features contain 101875 finite vertices.

## MATLAB schema
- countries: 1x199 struct, fields iso3, iso2, country, countryZh, capital, capitalZh, latitude, longitude, label, search, notes, unMember, source.
- boundaries: 1x242 struct, fields iso3, country, latitude, longitude.
- boundaryLatitude and boundaryLongitude: NaN-separated numeric column vectors for one plot call.
- recommended197Iso3: 1x197 cellstr for the approved default selection; the field name is retained for data compatibility.
- Rebuild offline: python tools/build_geodata.py, then MATLAB addpath('tools'); finalize_geodata. Native finalization preserves UTF-8 Chinese text on this MATLAB version.

## Validation
- Native MATLAB load: 199 capital records, 197 recommended records, 193 UN member flags; numeric boundary vectors valid.
- Chinese search checks for Beijing and Tokyo passed.
- Latitude range [-90,90], longitude range [-180,180], unique ISO3 codes and nonempty Chinese capital aliases verified.

## SHA-256 checksums
- `countries_geojson.json` `3e458fc036ad0a66411f2c1e6cac49c5d7bfb81cb1123bc513b22511a2b7fdeb`
- `populated_places.json` `fd3fa867a320cbd5c5b6bb5bc550afeec2939fb2cef688e508007282a55ac42f`
- `populated_places_full.json` `9b8e3de09048ef00dfc70357dbb9fa324493f214b5e0ae4daf1aa79a8d10116b`
- `mledoze_countries.json` `99b85dda36895c79caf72e191d035e4b9d82e811ee34f9ca15dfa67d7c561ba8`
- `capital_overrides.json` `4dee4a1d49c3100ee51ebf5f81c58c1a70c40351929aaa873e5789a11477ab4c`
- `nominatim_capitals_raw.json` `8cadc20b7f3700ff07bed28a28c1a463ae0e14e58c217791d278f5fbfcc72316`
- `capital_chinese_aliases.json` `9c806ed0a39e05dd86ae36e8985719688130c71564ecdfe9608af095335fd3c0`
- `nominatim_capital_names_raw.json` `431074bb6016d3b08b1ed4ff01240b2a5dee3880de8b767b79cf96fdb023e3eb`
- `countries_superset.json` `7d43433ab6eb0f12d3a197b21c463502b69c3a2c01978617a1c6cf59ca3bde3b`
- `countries_superset.csv` `57117646a2fcf6021d9d376e13cd9783c91fa239dee9717947198368946e21ac`
- `world_geodata.mat` `635644eca641087998ea4229e4903a335fc6f366816e830a7bb4aa8072a63ff7`
