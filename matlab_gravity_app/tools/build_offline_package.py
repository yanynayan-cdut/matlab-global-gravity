"""Build the self-contained MATLAB runtime ZIP (Python is build-time only).

The release contains only an explicit list of runtime files, sources/licenses,
user documentation, and MATLAB tests. Data reconstruction is not required.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
NAME = "GlobalGravity_MATLAB_R2022b_Offline"
OUTPUT = ROOT / "releases"
RUNTIME = [
    "START_HERE.m", "gravity_field_app.m", "gravity_at_location.m",
    "centrifugal_at_location.m", "gravity_project.m", "gravity_display_geometry.m",
    "gravity_viewport_color_limits.m", "load_surface_environment.m",
]
DATA = [
    "world_geodata.mat", "gravity_grid.mat", "gravity_egm2008_n180_coefficients.mat",
    "terrain_data.mat", "centrifugal_cache.mat", "countries_superset.csv",
    "countries_superset.json", "DATA_PROVENANCE.md", "COUNTRY_METADATA_LICENSE.txt",
    "geodata_source_versions.json", "gravity_model.md", "gravity_provenance.json",
    "terrain_sources.md", "terrain_provenance.json", "terrain_capital_diagnostics.json",
    "capital_overrides.json", "capital_chinese_aliases.json", "nominatim_capitals_raw.json",
    "nominatim_capital_names_raw.json", "terrain_raw/manifest.json",
]


def build() -> None:
    entries = {name: ROOT / name for name in RUNTIME}
    entries.update({"data/" + name: ROOT / "data" / name for name in DATA})
    entries["README.md"] = ROOT / "PACKAGE_README.md"
    entries["SOURCES.md"] = ROOT / "SOURCES.md"
    for folder, pattern in [("tests", "*.m"), ("docs", "*.md"), ("docs", "*.png"),
                            ("docs/brochure", "*.png")]:
        for source in sorted((ROOT / folder).glob(pattern)):
            entries[source.relative_to(ROOT).as_posix()] = source
    # A report is added after validation of the extracted runtime files.
    report = ROOT / "artifacts" / "offline_package_validation.md"
    tested_hashes = None
    if report.is_file():
        evidence = json.loads(report.with_suffix(".json").read_text(encoding="utf-8"))
        if (evidence["failed"] or evidence["incomplete"]
                or evidence["passed"] != evidence["testCount"]
                or evidence["requiredProducts"] != ["MATLAB"]):
            raise ValueError("The validation report does not confirm a successful base MATLAB run.")
        tested_hashes = evidence["validatedFileSHA256"]
        if set(tested_hashes) != set(entries):
            raise ValueError("The package file list changed; validate a fresh extracted package.")
        entries["VALIDATION.md"] = report
    payload = {name: source.read_bytes() for name, source in sorted(entries.items())}
    if tested_hashes is not None:
        for name, checksum in tested_hashes.items():
            if hashlib.sha256(payload[name]).hexdigest() != checksum:
                raise ValueError(f"File changed after package validation: {name}")
    manifest = {
        "package": NAME,
        "minimumMATLAB": "R2022b (9.13)",
        "entryPoint": "START_HERE.m",
        "additionalToolboxes": [],
        "networkRequired": False,
        "pythonRequiredAtRuntime": False,
        "files": [{"path": name, "bytes": len(data),
                   "sha256": hashlib.sha256(data).hexdigest()}
                  for name, data in payload.items()],
    }
    payload["PACKAGE_MANIFEST.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    OUTPUT.mkdir(exist_ok=True)
    archive_path = OUTPUT / (NAME + ".zip")
    with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in payload.items():
            info = zipfile.ZipInfo(NAME + "/" + name, date_time=(2026, 9, 28, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    with zipfile.ZipFile(archive_path) as archive:
        assert archive.testzip() is None, "Archive CRC validation failed"
        for item in manifest["files"]:
            data = archive.read(NAME + "/" + item["path"])
            assert hashlib.sha256(data).hexdigest() == item["sha256"], item["path"]
    checksum = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    archive_path.with_suffix(".sha256").write_text(f"{checksum}  {archive_path.name}\n", encoding="ascii")
    print(json.dumps({"archive": str(archive_path), "files": len(payload),
                      "bytes": archive_path.stat().st_size, "sha256": checksum}, indent=2))


if __name__ == "__main__":
    build()
