"""Rebuild the bundled EGM2008 degree-180 coefficients and one-degree grid.

Requires Python + NumPy + SciPy (development only; running the MATLAB app
requires no Python). The model is downloaded from the official ICGEM catalogue.
No fallback or fabricated values are used. --archive can reuse a local download.
"""
from __future__ import annotations
import argparse
import hashlib
import io
import json
from pathlib import Path
import urllib.request
import zipfile
from datetime import datetime, timezone
import numpy as np
from scipy.io import savemat

URL = "https://icgem.gfz-potsdam.de/getmodel/zip/c50128797a9cb62e936337c890e4425f03f0461d7329b09a8cc8561504465340/EGM2008.zip"
ARCHIVE_SHA256 = "8cb3521f9650568a80d049bd6dd3668a4191f3ac9d741122cc0321bcc28948e3"
ROOT = Path(__file__).resolve().parents[1]
A = 6378137.0
F = 1 / 298.257223563
OMEGA = 7.292115e-5
E2 = F * (2 - F)


def normalized_legendre(phi, degree):
    """4-pi normalized, no Condon-Shortley phase; derivative w.r.t. latitude."""
    s, c = np.sin(phi), np.cos(phi)
    p2 = np.zeros((len(phi), degree + 1))
    d2 = np.zeros_like(p2)
    p1, d1 = p2.copy(), d2.copy()
    p1[:, 0] = 1
    yield 0, p1, d1
    for n in range(1, degree + 1):
        p, d = np.zeros_like(p1), np.zeros_like(d1)
        k = np.sqrt(3) if n == 1 else np.sqrt((2 * n + 1) / (2 * n))
        p[:, n] = k * c * p1[:, n - 1]
        d[:, n] = k * (-s * p1[:, n - 1] + c * d1[:, n - 1])
        k = np.sqrt(2 * n + 1)
        p[:, n - 1] = k * s * p1[:, n - 1]
        d[:, n - 1] = k * (c * p1[:, n - 1] + s * d1[:, n - 1])
        for m in range(n - 1):
            aa = np.sqrt((2 * n - 1) * (2 * n + 1) / ((n - m) * (n + m)))
            bb = np.sqrt((2 * n + 1) * (n + m - 1) * (n - m - 1)
                         / ((n - m) * (n + m) * (2 * n - 3)))
            p[:, m] = aa * s * p1[:, m] - bb * p2[:, m]
            d[:, m] = aa * (c * p1[:, m] + s * d1[:, m]) - bb * d2[:, m]
        yield n, p, d
        p2, p1, d2, d1 = p1, p, d1, d


def synthesize(lat, lon, cnm, snm, gm, reference_radius, height=0):
    """All latitudes crossed with all longitudes, WGS84 ellipsoidal height."""
    phi_g = np.deg2rad(lat)
    prime = A / np.sqrt(1 - E2 * np.sin(phi_g) ** 2)
    rho = (prime + height) * np.cos(phi_g)
    z = (prime * (1 - E2) + height) * np.sin(phi_g)
    radius = np.hypot(rho, z)
    phi = np.arctan2(z, rho)
    degree = len(cnm) - 1
    ar, br, ap, bp, al, bl = [np.zeros((len(lat), degree + 1)) for _ in range(6)]
    for n, p, dp in normalized_legendre(phi, degree):
        q = (reference_radius / radius) ** n
        for m in range(n + 1):
            pp = q * p[:, m]
            dd = q * dp[:, m]
            ar[:, m] -= (n + 1) * pp * cnm[n, m]
            br[:, m] -= (n + 1) * pp * snm[n, m]
            ap[:, m] += dd * cnm[n, m]
            bp[:, m] += dd * snm[n, m]
            al[:, m] += m * pp * snm[n, m]
            bl[:, m] -= m * pp * cnm[n, m]
    angles = np.arange(degree + 1)[:, None] * np.deg2rad(lon)[None, :]
    cc, ss = np.cos(angles), np.sin(angles)
    scale = gm / radius[:, None] ** 2
    gr = scale * (ar @ cc + br @ ss) + OMEGA ** 2 * radius[:, None] * np.cos(phi[:, None]) ** 2
    gp = scale * (ap @ cc + bp @ ss) - OMEGA ** 2 * radius[:, None] * np.sin(phi[:, None]) * np.cos(phi[:, None])
    gl = scale * (al @ cc + bl @ ss) / np.cos(phi[:, None])
    gravity = np.sqrt(gr ** 2 + gp ** 2 + gl ** 2)
    normal = 9.7803253359 * (1 + 0.00193185265241 * np.sin(phi_g) ** 2) / np.sqrt(1 - E2 * np.sin(phi_g) ** 2)
    mrot = OMEGA ** 2 * A ** 2 * (A * (1 - F)) / 3.986004418e14
    normal *= 1 - 2 * (1 + F + mrot - 2 * F * np.sin(phi_g) ** 2) * height / A + 3 * height ** 2 / A ** 2
    return gravity, gravity - normal[:, None], (gr, gp, gl)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--degree", type=int, choices=[180], default=180,
                        help="The UI and native evaluator use the bundled degree-180 model.")
    args = parser.parse_args()
    data_dir = ROOT / "data"
    data_dir.mkdir(exist_ok=True)
    archive = args.archive or ROOT / ".cache" / "EGM2008.zip"
    if not archive.exists():
        archive.parent.mkdir(parents=True, exist_ok=True)
        print(f"Downloading {URL}", flush=True)
        urllib.request.urlretrieve(URL, archive)
    archive_hash = hashlib.sha256(archive.read_bytes()).hexdigest()
    if archive_hash != ARCHIVE_SHA256:
        raise RuntimeError("EGM2008 archive checksum differs from the validated source. Inspect the download before continuing.")
    cnm = np.zeros((args.degree + 1, args.degree + 1))
    snm = np.zeros_like(cnm)
    header = {}
    records = []
    terms = set()
    with zipfile.ZipFile(archive) as z:
        member = next(name for name in z.namelist() if name.endswith(".gfc"))
        with z.open(member) as stream:
            for line in io.TextIOWrapper(stream, encoding="ascii", errors="replace"):
                fields = line.split()
                if not fields:
                    continue
                if fields[0] == "gfc":
                    n, m = int(fields[1]), int(fields[2])
                    if n <= args.degree:
                        if (n, m) in terms or not 0 <= m <= n:
                            raise RuntimeError("Invalid or repeated harmonic coefficient")
                        terms.add((n, m))
                        cnm[n, m] = float(fields[3].replace("D", "E").replace("d", "e"))
                        snm[n, m] = float(fields[4].replace("D", "E").replace("d", "e"))
                        records.append(line.rstrip())
                elif len(fields) > 1 and fields[0] in ("modelname", "earth_gravity_constant", "radius", "max_degree", "norm", "tide_system"):
                    header[fields[0]] = fields[1]
    gm, radius = float(header["earth_gravity_constant"]), float(header["radius"])
    # Degree-one terms vanish in the Earth-centred frame and are omitted by
    # the source. Do not silently tolerate any other missing coefficient.
    expected = {(n, m) for n in range(args.degree + 1) for m in range(n + 1)}
    assert expected - terms == {(1, 0), (1, 1)}
    assert len(records) == (args.degree + 1) * (args.degree + 2) // 2 - 2
    assert cnm[0, 0] == 1 and header["norm"] == "fully_normalized"
    stem = f"gravity_egm2008_n{args.degree}"
    # Preserve source numbers, normalization and tide system in a readable extract.
    extract = data_dir / f"{stem}.gfc"
    extract.write_text("# Exact coefficient subset from ICGEM EGM2008; see gravity_provenance.json\n"
                       + "\n".join(f"{k} {v}" for k, v in header.items() if k != "max_degree")
                       + f"\nmax_degree {args.degree}\nend_of_head\n" + "\n".join(records) + "\n", encoding="ascii")
    savemat(data_dir / f"{stem}_coefficients.mat", {"C": cnm, "S": snm, "GM": gm,
            "referenceRadius": radius, "degree": args.degree, "modelName": "EGM2008",
            "sourceURL": URL, "tideSystem": header.get("tide_system", "tide_free")}, do_compression=True)
    lat, lon = np.arange(-90, 91, dtype=float), np.arange(-180, 181, dtype=float)
    gravity, disturbance, _ = synthesize(lat, lon, cnm, snm, gm, radius)
    savemat(data_dir / "gravity_grid.mat", {"lat": lat, "lon": lon, "g": gravity,
            "disturbance": disturbance, "normalGravity": gravity - disturbance, "degree": args.degree,
            "modelName": "EGM2008", "height": 0., "heightReference": "WGS84 ellipsoidal height (m)",
            "sourceURL": URL}, do_compression=True)
    metadata = {"model": "EGM2008", "source_url": URL, "catalogue_url": "https://icgem.gfz-potsdam.de/tom_longtime",
                "reference_doi": "10.1029/2011JB008916",
                "archive_saved_at_utc": datetime.fromtimestamp(archive.stat().st_mtime, timezone.utc).isoformat(),
                "grid_generated_at_utc": datetime.now(timezone.utc).isoformat(),
                "source_archive_sha256": archive_hash, "coefficient_extract_sha256": hashlib.sha256(extract.read_bytes()).hexdigest(),
                "original_max_degree": header["max_degree"], "retained_degree_order": args.degree, "coefficient_count": len(records),
                "normalization": "fully_normalized (4pi); no Condon-Shortley phase", "tide_system": header.get("tide_system"),
                "grid_shape": list(gravity.shape), "grid_spacing_degrees": 1, "coordinates": "WGS84 geodetic latitude and longitude",
                "height_reference": "WGS84 ellipsoid; grid h=0 m", "g_units": "m/s^2", "disturbance_units": "m/s^2",
                "definition_g": "Magnitude of model gravitational acceleration plus centrifugal acceleration",
                "definition_disturbance": "g minus WGS84 Somigliana normal gravity on the ellipsoid",
                "data_basis": "NGA EGM2008 fitted to satellite, terrestrial, airborne and altimetry-derived observations",
                "limitations": ["Not direct gravimeter observations at every grid point", "Truncated at degree/order 180 (~111 km half wavelength); not local terrain-scale gravity", "Grid is at ellipsoidal height zero, not terrain or geoid surface", "Displayed relief is an exaggerated encoding of the field, not Earth topography"],
                "range_g": [float(gravity.min()), float(gravity.max())], "range_disturbance_mgal": [float(disturbance.min()*1e5), float(disturbance.max()*1e5)]}
    (data_dir / "gravity_provenance.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(metadata, indent=2), flush=True)


if __name__ == "__main__":
    main()
