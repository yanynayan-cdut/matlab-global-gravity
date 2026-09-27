"""Fetch small official NOAA ETOPO2022 subsets and build MATLAB terrain data.

No full global rasters are downloaded. Cached response bodies make rebuilds
offline/reproducible. Requires Python, requests, NumPy and SciPy for development;
the MATLAB app only needs the resulting terrain_data.mat file.
"""
from __future__ import annotations

import argparse
import concurrent.futures
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import struct
import sys
import threading
import time

import numpy as np
import requests
from scipy.io import savemat

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data"
RAW = DATA / "terrain_raw"
DODS = "https://www.ngdc.noaa.gov/thredds/dodsC/"
PRODUCT = "https://www.ncei.noaa.gov/products/etopo-global-relief-model"
GUIDE = "https://www.ngdc.noaa.gov/mgg/global/relief/ETOPO2022/docs/1.2%20ETOPO%202022%20User%20Guide.pdf"
MANIFEST_FILE = RAW / "manifest.json"
LOCK = threading.Lock()
MANIFEST = json.loads(MANIFEST_FILE.read_text(encoding="utf-8")) if MANIFEST_FILE.exists() else {}
LOCAL = threading.local()
# Explicitly approved coastal/offshore canonical points. Other negative
# elevations remain untouched because they may represent legitimate
# below-sea-level land.
RELOCATE_ISO3 = {"BHS", "COK", "MDV", "MHL", "NRU"}


def utc():
    return datetime.now(timezone.utc).isoformat()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def fetch(url, extension="dods"):
    """Fetch/check cached bytes, retry transient failures, record every subset."""
    key = sha(url.encode())
    file = RAW / f"{key}.{extension}"
    with LOCK:
        entry = MANIFEST.get(key)
    if file.exists() and entry:
        content = file.read_bytes()
        if sha(content) != entry["sha256"]:
            raise RuntimeError(f"Cached response checksum mismatch: {file}")
        return content
    if file.exists():
        # A lost manifest can be reconstructed without discarding the original
        # server response. Mark the recovery explicitly: the HTTP headers and
        # the exact response URL are no longer available in that case.
        content = file.read_bytes()
        if extension == "dods" and b"\nData:\n" not in content:
            raise RuntimeError(f"Invalid cached DAP2 response: {file}")
        entry = {"request_url": url,
                 "cached_body_saved_at_utc": datetime.fromtimestamp(file.stat().st_mtime, timezone.utc).isoformat(),
                 "sha256": sha(content), "bytes": len(content), "file": file.name,
                 "manifest_recovered_from_cached_body": True,
                 "recovery_note": "Original decoded source response retained; response headers and redirect URL not retained."}
        with LOCK:
            MANIFEST[key] = entry
            MANIFEST_FILE.write_text(json.dumps(MANIFEST, indent=2) + "\n", encoding="utf-8")
        return content
    if not hasattr(LOCAL, "session"):
        LOCAL.session = requests.Session()
    for attempt in range(4):
        try:
            response = LOCAL.session.get(url, timeout=(15, 75))
            response.raise_for_status()
            content = response.content
            if extension == "dods" and b"\nData:\n" not in content:
                raise RuntimeError(f"Expected DAP2 data but received {content[:120]!r}")
            file.write_bytes(content)
            entry = {"request_url": url, "resolved_url": response.url,
                     "fetched_at_utc": utc(), "sha256": sha(content),
                     "bytes": len(content), "file": file.name,
                     "last_modified": response.headers.get("Last-Modified", ""),
                     "etag": response.headers.get("ETag", "")}
            with LOCK:
                MANIFEST[key] = entry
                MANIFEST_FILE.write_text(json.dumps(MANIFEST, indent=2) + "\n", encoding="utf-8")
            return content
        except (requests.RequestException, RuntimeError) as error:
            if attempt == 3:
                raise RuntimeError(f"Failed source query: {url}") from error
            time.sleep(2 ** attempt)
    raise AssertionError("Unreachable")


def path60(kind):
    folder = "60s_surface_elev_netcdf" if kind == "surface" else "60s_geoid_netcdf"
    return f"global/ETOPO2022/60s/{folder}/ETOPO_2022_v1_60s_N90W180_{kind}.nc"


def path15(kind, latitude, longitude):
    west = int(np.floor(longitude / 15) * 15)
    north = int(np.floor(latitude / 15) * 15 + 15)
    name = f"{'N' if north >= 0 else 'S'}{abs(north):02d}{'E' if west >= 0 else 'W'}{abs(west):03d}"
    folder = "15s_surface_elev_netcdf" if kind == "surface" else "15s_geoid_netcdf"
    return f"global/ETOPO2022/15s/{folder}/ETOPO_2022_v1_15s_{name}_{kind}.nc", north - 15, west


def parse_dods(content):
    """Decode the three fixed-type arrays in this dataset's DAP2 Grid z."""
    head, blob = content.split(b"\nData:\n", 1)
    match = re.search(rb"Float32 z\[lat = (\d+)\]\[lon = (\d+)\]", head)
    if not match:
        raise RuntimeError("Unexpected ETOPO DAP schema")
    nlat, nlon = map(int, match.groups())
    pos = 0
    arrays = []
    for count, dtype in ((nlat * nlon, ">f4"), (nlat, ">f8"), (nlon, ">f8")):
        a, b = struct.unpack_from(">II", blob, pos)
        pos += 8
        if (a, b) != (count, count):
            raise RuntimeError("Unexpected DAP2 array length")
        array = np.frombuffer(blob, dtype=dtype, count=count, offset=pos).astype(float)
        pos += count * np.dtype(dtype).itemsize
        arrays.append(array)
    if pos != len(blob):
        raise RuntimeError("Unexpected bytes after the ETOPO DAP2 grid")
    z, lat, lon = arrays
    z = z.reshape(nlat, nlon)
    if not np.all(np.isfinite(z)) or np.max(np.abs(z)) > 12000:
        raise RuntimeError("Missing/invalid ETOPO heights in source subset")
    return z, lat, lon


def query(dataset, y, x):
    url = DODS + dataset + f".dods?z[{y}][{x}]"
    return parse_dods(fetch(url)), url


def global_grid(kind):
    """Bilinear 60s data at exact integer-degree points, periodic seam."""
    dataset = path60(kind)
    specs = [("59:60:10739", "59:60:21599"),
             ("59:60:10739", "0:60:21540"),
             ("60:60:10740", "59:60:21599"),
             ("60:60:10740", "0:60:21540"),
             ("0:1:0", "0:60:21540"),
             ("10799:1:10799", "0:60:21540")]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(lambda p: query(dataset, *p), specs))
    lowlow, lowhigh, highlow, highhigh = [result[0][0] for result in results[:4]]
    # The low-longitude phase is shifted once across the antimeridian.
    interior = (np.roll(lowlow, 1, axis=1) + lowhigh
                + np.roll(highlow, 1, axis=1) + highhigh) / 4
    assert interior.shape == (179, 360)
    south = np.mean(results[4][0][0])
    north = np.mean(results[5][0][0])
    grid = np.vstack((np.full((1, 360), south), interior, np.full((1, 360), north)))
    grid = np.column_stack((grid, grid[:, 0]))
    return grid, [result[1] for result in results]


def capital_query(country, kind):
    lat, lon = country["latitude"], country["longitude"]
    dataset, south, west = path15(kind, lat, lon)
    yi, xi = (lat - south) * 240 - .5, (lon - west) * 240 - .5
    # A small surrounding window supports coastal diagnostics; interpolation
    # still uses the exact recorded capital coordinates and is never clamped.
    y0, y1 = max(0, int(np.floor(yi)) - 2), min(3599, int(np.ceil(yi)) + 2)
    x0, x1 = max(0, int(np.floor(xi)) - 2), min(3599, int(np.ceil(xi)) + 2)
    (z, ys, xs), url = query(dataset, f"{y0}:1:{y1}", f"{x0}:1:{x1}")
    if not ys[0] <= lat <= ys[-1] or not xs[0] <= lon <= xs[-1]:
        raise RuntimeError(f"Capital {country['iso3']} lies too close to a tile boundary; explicitly stitch adjacent tiles")
    # Apply separable bilinear interpolation using coordinates returned by NOAA.
    value = float(np.interp(lat, ys, [np.interp(lon, xs, row) for row in z]))
    iy, ix = np.argmin(np.abs(ys - lat)), np.argmin(np.abs(xs - lon))
    detail = {"url": url, "interpolated_m": value,
              "nearest_cell_m": float(z[iy, ix]), "window_min_m": float(z.min()),
              "window_max_m": float(z.max()), "resolution_arc_seconds": 15}
    if kind == "surface":
        dl, dp = np.meshgrid((xs - lon) * np.cos(np.deg2rad(lat)), ys - lat)
        distance = np.hypot(dl, dp) * 111195
        # Strictly positive source cells avoid treating a sea-level 0 cell as
        # proof of valid land. Relocation is restricted to the five approved
        # records above; no generic negative-height fallback is allowed.
        candidates = (z > 0) & (distance <= 1500) & (country["iso3"] in RELOCATE_ISO3)
        if candidates.any():
            j, i = np.unravel_index(np.argmin(np.where(candidates, distance, np.inf)), z.shape)
            detail["nearest_nonnegative_cell"] = {"latitude": float(ys[j]), "longitude": float(xs[i]),
                                                   "elevation_m": float(z[j, i]), "distance_m": float(distance[j, i])}
        detail["review_flag"] = bool(value < 0)
        if country["iso3"] in RELOCATE_ISO3 and detail["review_flag"] and "nearest_nonnegative_cell" not in detail:
            raise RuntimeError(f"No valid positive land-cell candidate within 1.5 km for approved capital {country['iso3']}")
        if country["iso3"] in RELOCATE_ISO3 and detail["review_flag"]:
            cell = detail["nearest_nonnegative_cell"]
            detail.update(effective_elevation_m=cell["elevation_m"],
                          effective_latitude=cell["latitude"], effective_longitude=cell["longitude"],
                          effective_distance_m=cell["distance_m"], effective_is_estimate=True,
                          effective_method="nearby land-cell estimate: nearest strictly positive ETOPO 15s cell within 1.5 km")
        else:
            detail.update(effective_elevation_m=value, effective_latitude=float(lat),
                          effective_longitude=float(lon), effective_distance_m=0.0,
                          effective_is_estimate=False,
                          effective_method="15s bilinear at canonical capital")
    return country["iso3"], kind, value, detail


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--workers", type=int, default=6, choices=range(1, 9))
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")
    RAW.mkdir(parents=True, exist_ok=True)
    if MANIFEST_FILE.exists():
        MANIFEST.update(json.loads(MANIFEST_FILE.read_text(encoding="utf-8")))
    # Verified per-file metadata are preferred over the THREDDS catalog's
    # inherited legacy ETOPO1 description.
    sources = [PRODUCT, GUIDE]
    for source in sources:
        fetch(source, "pdf" if source.endswith("pdf") else "html")
    for kind in ("surface", "geoid"):
        fetch(DODS + path60(kind) + ".das", "das")
        fetch(DODS + path60(kind) + ".dds", "dds")
    print("Fetching the 60s global bilinear subsets...", flush=True)
    elevation, elevation_urls = global_grid("surface")
    geoid, geoid_urls = global_grid("geoid")
    country_file = DATA / "countries_superset.json"
    geography = json.loads(country_file.read_text(encoding="utf-8"))
    selected = set(geography["recommended197Iso3"])
    capitals = [c for c in geography["countries"] if c["iso3"] in selected]
    assert len(capitals) == 197
    work = [(c, kind) for c in capitals for kind in ("surface", "geoid")]
    values = {}
    diagnostics = {}
    print("Fetching 15s capital windows (surface and matching EGM2008 geoid)...", flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(capital_query, c, kind) for c, kind in work]
        for count, future in enumerate(concurrent.futures.as_completed(futures), 1):
            iso, kind, value, detail = future.result()
            values[iso, kind] = value
            diagnostics.setdefault(iso, {})[kind] = detail
            if count % 40 == 0 or count == len(work):
                print(f"Capital subsets: {count}/{len(work)}", flush=True)
    field = lambda key: np.asarray([c[key] for c in capitals])
    raw_heights = np.array([values[c["iso3"], "surface"] for c in capitals])
    surface_details = [diagnostics[c["iso3"]]["surface"] for c in capitals]
    heights = np.array([d["effective_elevation_m"] for d in surface_details])
    sample_lat = np.array([d["effective_latitude"] for d in surface_details])
    sample_lon = np.array([d["effective_longitude"] for d in surface_details])
    sample_distance = np.array([d["effective_distance_m"] for d in surface_details])
    sample_estimate = np.array([d["effective_is_estimate"] for d in surface_details], dtype=bool)
    undulations = np.array([values[c["iso3"], "geoid"] for c in capitals])
    sample_geoid = undulations.copy()
    for i, c in enumerate(capitals):
        if not sample_estimate[i]:
            continue
        url = diagnostics[c["iso3"]]["geoid"]["url"]
        zz, ys, xs = parse_dods(fetch(url))
        sample_geoid[i] = float(np.interp(sample_lat[i], ys,
            [np.interp(sample_lon[i], xs, row) for row in zz]))
        diagnostics[c["iso3"]]["geoid"]["effective_sample"] = {
            "latitude": float(sample_lat[i]), "longitude": float(sample_lon[i]),
            "geoid_m": float(sample_geoid[i]), "url": url}
    source = "NOAA NCEI ETOPO2022 v1 Ice Surface + accompanying EGM2008 geoid; 60s global / 15s capitals"
    savemat(DATA / "terrain_data.mat", {
        "lat": np.arange(-90, 91, dtype=float), "lon": np.arange(-180, 181, dtype=float),
        "elevationM": elevation, "geoidUndulationM": geoid,
        "capitalIso3": field("iso3").astype(object), "capitalLatitude": field("latitude"),
        "capitalLongitude": field("longitude"), "capitalElevationM": heights,
        "capitalRawElevationM": raw_heights, "capitalGeoidM": undulations,
        "capitalSampleGeoidM": sample_geoid,
        "capitalElevationSampleLatitude": sample_lat,
        "capitalElevationSampleLongitude": sample_lon,
        "capitalElevationSampleDistanceM": sample_distance,
        "capitalElevationIsEstimate": sample_estimate,
        "capitalElevationMethod": np.asarray([d["effective_method"] for d in surface_details], dtype=object),
        "capitalReviewFlag": raw_heights < 0,
        "source": source, "verticalDatum": "EGM2008 height EPSG:3855", "ellipsoidHeightFormula": "h = H + N",
        "geoidPolicy": "ETOPO2022 accompanying EGM2008 grid; add geoidUndulationM to elevationM",
        "oceanPolicy": "Original negative seabed elevation retained; no sea-level clamp",
        "globalResolutionArcSec": 60, "capitalResolutionArcSec": 15,
        "capitalMethod": "Bilinear at canonical capital; only approved BHS/COK/MDV/MHL/NRU use nearby strictly-positive 15s land cells within 1.5 km",
        "capitalSampleGeoidMethod": "Geoid at effective elevation sample; application uses canonical-coordinate capitalGeoidM",
    }, do_compression=True, oned_as="row")
    diagnostic_file = DATA / "terrain_capital_diagnostics.json"
    diagnostic_file.write_text(json.dumps(diagnostics, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    provenance = {
        "generated_at_utc": utc(), "dataset": source, "source_doi": "10.25921/fd45-gt74",
        "official_product_url": PRODUCT, "official_user_guide_url": GUIDE,
        "vertical_datum": "EGM2008 gravity-related height, EPSG:3855; metres positive up",
        "horizontal_datum": "WGS84 EPSG:4326, geodetic latitude/longitude in degrees",
        "height_conversion": "h_WGS84 = H_ETOPO2022 + N_geoid (user guide section 2.2)",
        "geoid_source": "ETOPO accompanying EGM2008 grid derived from NGA egm08_25.gtx (2.5 arc-minute source), resampled by NOAA",
        "ocean_policy": "Original negative seabed values retained. Surface means ice surface in Greenland/Antarctica; ocean points represent seafloor.",
        "license": "ETOPO user guide section 4: freely usable for private, academic and commercial purposes; cite NOAA NCEI (2022), DOI above. Geoid metadata: Derived from work by NGA. Public Domain.",
        "global_method": "Bilinear interpolation of four 60-arc-second cell centers surrounding each exact integer-degree interior point. Periodic longitude seam duplicated. At each geographic pole use the longitudinal mean of the nearest source row, sampled every degree.",
        "capital_method": "Bilinear interpolation at canonical coordinates. Only user-approved BHS/COK/MDV/MHL/NRU use the nearest strictly positive ETOPO 15s source cell within the local 6x6-cell window and 1.5 km distance limit. No other negative capital is relocated. Zero cells are excluded. Original values/coordinates are retained.",
        "capital_warning": "15 arc seconds is about 460 m at the equator and does not guarantee city-site height accuracy. Relocated values are estimates for nearby valid land cells; their sampling distances are stored in capitalElevationSampleDistanceM.",
        "global_grid_shape": [181, 361], "capital_count": len(capitals),
        "global_queries": {"surface": elevation_urls, "geoid": geoid_urls},
        "request_manifest": "terrain_raw/manifest.json", "request_manifest_sha256": sha(MANIFEST_FILE.read_bytes()),
        "request_hash_definition": "SHA256 of decoded HTTP response body; each exact DAP query and retrieval time is in the manifest",
        "geography_input_sha256": sha(country_file.read_bytes()),
        "terrain_data_sha256": sha((DATA / "terrain_data.mat").read_bytes()),
        "capital_diagnostics_sha256": sha(diagnostic_file.read_bytes()),
        "ranges_m": {"global_elevation": [float(elevation.min()), float(elevation.max())],
                     "global_geoid": [float(geoid.min()), float(geoid.max())],
                     "capital_raw_elevation": [float(raw_heights.min()), float(raw_heights.max())],
                     "capital_effective_elevation": [float(heights.min()), float(heights.max())]},
        "capital_negative_flags": [{"iso3": c["iso3"], "capital": c["capital"],
                                    "raw_elevation_m": float(raw_heights[i]),
                                    "effective_elevation_m": float(heights[i]),
                                    "sample_distance_m": float(sample_distance[i]),
                                    "nearest_cell_m": diagnostics[c["iso3"]]["surface"]["nearest_cell_m"]}
                                   for i, c in enumerate(capitals) if raw_heights[i] < 0],
        "capital_effective_estimate_count": int(sample_estimate.sum()),
        "capital_geoid_policy": "Calculator retains canonical capital latitude/longitude and locally sampled capitalGeoidM; H is explicitly a nearby-land estimate for five capitals. Sample-coordinate N is additionally stored in capitalSampleGeoidM for provenance.",
    }
    (DATA / "terrain_provenance.json").write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ranges_m": provenance["ranges_m"], "negative_flags": provenance["capital_negative_flags"]}, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    main()
