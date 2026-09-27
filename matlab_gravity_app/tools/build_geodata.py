"""Rebuild MATLAB geography from pinned Natural Earth and mledoze source snapshots.

Only data/world_geodata.mat and derived data files are written. Python is needed
for this optional build step only; the MATLAB application loads the bundled MAT.
"""
from pathlib import Path
import collections
import csv
import hashlib
import json
import math
import re
import unicodedata
import numpy as np
from scipy.io import savemat

ROOT = Path(__file__).resolve().parents[1] / "data"
metadata = json.loads((ROOT / "mledoze_countries.json").read_text(encoding="utf8"))
places = json.loads((ROOT / "populated_places.json").read_text(encoding="utf8"))["features"]
geography = json.loads((ROOT / "countries_geojson.json").read_text(encoding="utf8"))["features"]

def normalize(value):
    return re.sub(r"[^a-z0-9]", "", unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode().lower())

def structs(rows):
    result = np.empty((1, len(rows)), dtype=[(key, object) for key in rows[0]])
    for i, row in enumerate(rows):
        for key, value in row.items():
            result[key][0, i] = value
    return result

by_iso2 = collections.defaultdict(list)
for feature in places:
    by_iso2[feature["properties"]["iso_a2"]].append(feature)

# Source mledoze incorrectly marks Vatican City as a UN member. Correct this
# against the UN member list (193); Holy See and Palestine are observers.
un_codes = {c["cca3"] for c in metadata if c.get("unMember") and c["cca3"] != "VAT"}
assert len(un_codes) == 193
recommended = un_codes | {"VAT", "PSE", "COK", "NIU"}
superset = recommended | {"TWN", "UNK"}

# Name matching overrides refer to existing Natural Earth city points. They do
# not substitute country centroid coordinates for capitals.
preferred_names = {"BOL": "Sucre", "ZAF": "Pretoria", "CIV": "Yamoussoukro", "BDI": "Gitega", "SWZ": "Mbabane", "LKA": "Sri Jayewardenepura Kotte", "NLD": "Amsterdam", "PSE": "Ramallah", "SSD": "Juba", "AND": "Andorra", "KIR": "Tarawa", "BRN": "Bandar Seri Begawan"}
place_aliases = {"DNK": "København", "GRD": "Saint George's", "LKA": "Sri Jayawardenepura Kotte", "MNG": "Ulaanbaatar", "SMR": "San Marino"}
special_notes = {
    "BOL": "宪法首都苏克雷；拉巴斯为政府所在地。",
    "ZAF": "此处选行政首都比勒陀利亚；另有立法首都开普敦、司法首都布隆方丹。",
    "CIV": "法定首都亚穆苏克罗；阿比让仍有部分政府机构。",
    "NLD": "宪法首都阿姆斯特丹；政府所在地为海牙。",
    "SWZ": "此处选行政首都姆巴巴内；洛班巴为王室及立法中心。",
    "LKA": "此处选立法首都斯里贾亚瓦德纳普拉科特；科伦坡为行政商业中心。",
    "MYS": "首都吉隆坡；布城为联邦行政中心。",
    "BEN": "法定首都波多诺伏；科托努为政府所在地。",
    "TZA": "首都多多马；达累斯萨拉姆为原首都。",
    "BDI": "2019 年迁都基特加；布琼布拉为经济中心。",
    "PSE": "此处采用行政中心拉姆安拉坐标；东耶路撒冷为其所主张的首都。",
    "ISR": "采用数据源的耶路撒冷坐标；该城市地位存在国际争议。",
    "NRU": "瑙鲁没有正式首都；亚伦为政府所在地。",
    "CHE": "伯尔尼为联邦城市及联邦政府所在地。",
    "IDN": "数据源采用雅加达；努山塔拉迁都计划仍应按最新法令核实。",
    "EGY": "数据源采用开罗；政府部门向新行政首都搬迁不直接改变此数据记录。",
    "COK": "库克群岛为与新西兰自由联合的自治国家。",
    "NIU": "纽埃为与新西兰自由联合的自治国家。",
    "VAT": "联合国观察员为圣座；地图点位为梵蒂冈城。",
}

# Missing tiny-country capital points are sourced separately, never inferred.
# The source metadata records are kept alongside these values.
manual_file = ROOT / "capital_overrides.json"
manual = json.loads(manual_file.read_text(encoding="utf8")) if manual_file.exists() else {}
aliases_file = ROOT / "capital_chinese_aliases.json"
capital_aliases = json.loads(aliases_file.read_text(encoding="utf8"))["records"] if aliases_file.exists() else {}

rows = []
unmatched = []
for country in sorted((c for c in metadata if c["cca3"] in superset), key=lambda c: c["cca3"]):
    iso = country["cca3"]
    code = "XKX" if iso == "UNK" else iso
    candidates = by_iso2[country["cca2"]]
    if iso == "UNK":
        candidates = [f for f in places if f["properties"]["adm0_a3"] == "KOS"]
    names = [preferred_names[iso]] if iso in preferred_names else country.get("capital", [])
    chosen = None
    for name in names:
        match_name = place_aliases.get(iso, name)
        matches = [f for f in candidates if normalize(f["properties"]["name"]) == normalize(match_name) or normalize(f["properties"].get("nameascii") or "") == normalize(match_name)]
        if matches:
            chosen = matches[0]
            break
    if iso in manual:
        override = manual[iso]
        capital = override["capital"]
        lat, lon = override["latitude"], override["longitude"]
        source = override["source"]
    elif chosen:
        props = chosen["properties"]
        capital = names[0] if len(names) == 1 else props["name"]
        lon, lat = chosen["geometry"]["coordinates"]
        source = "Natural Earth 10m populated places; ne_id=" + str(props["ne_id"])
    else:
        unmatched.append((iso, country["name"]["common"], names, [(f["properties"]["name"],f["properties"]["adm0cap"]) for f in candidates if f["properties"]["adm0cap"] or f["properties"]["capalt"]]))
        continue
    zh = country["translations"].get("zho", {}).get("common", country["name"]["common"])
    en = country["name"]["common"]
    aliases = " ".join(country.get("altSpellings", []))
    capital_zh = capital_aliases.get(code, {}).get("nameZh", "")
    rows.append({"iso3":code,"iso2":country["cca2"],"country":en,"countryZh":zh,"capital":capital,"capitalZh":capital_zh,"latitude":float(lat),"longitude":float(lon),"label":f"{zh} / {en} — {capital}","search":f"{zh} {en} {capital} {capital_zh} {code} {country['cca2']} {aliases}".lower(),"notes":special_notes.get(iso,""),"unMember":bool(iso in un_codes),"source":source})

if unmatched:
    print(json.dumps({"unmatched": unmatched}, ensure_ascii=True, indent=2))
    raise SystemExit("Resolve all unmatched capitals before producing MAT data.")

boundaries = []
for feature in geography:
    props = feature["properties"]
    geometry = feature["geometry"]
    polygons = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
    latitudes, longitudes = [], []
    for polygon in polygons:
        for ring in polygon:
            for i, point in enumerate(ring):
                lon, lat = point[:2]
                if i:
                    oldlon, oldlat = ring[i-1][:2]
                    dlon = lon - oldlon
                    # Break at the dateline for 2D views. Each coastline remains
                    # correct in spherical view, avoiding a false world chord.
                    if abs(dlon) > 180:
                        latitudes.append(float("nan")); longitudes.append(float("nan"))
                    else:
                        steps = max(1, math.ceil(max(abs(dlon), abs(lat-oldlat)) / 0.5))
                        for j in range(1,steps):
                            latitudes.append(oldlat+(lat-oldlat)*j/steps)
                            longitudes.append(oldlon+dlon*j/steps)
                latitudes.append(lat); longitudes.append(lon)
            latitudes.append(float("nan")); longitudes.append(float("nan"))
    iso = props.get("ISO_A3_EH")
    if not iso or iso == "-99": iso = props.get("ADM0_A3", "")
    boundaries.append({"iso3":iso,"country":props["NAME_EN"],"latitude":np.asarray(latitudes).reshape(-1,1),"longitude":np.asarray(longitudes).reshape(-1,1)})

all_lat = np.concatenate([b["latitude"] for b in boundaries])
all_lon = np.concatenate([b["longitude"] for b in boundaries])
output={"boundaries":structs(boundaries),"boundaryLatitude":all_lat,"boundaryLongitude":all_lon,"recommended197Iso3":np.array(sorted(recommended),dtype=object),"sourceNote":"Natural Earth 50m borders + 10m city points; mledoze country names; 2026-09-27"}
# MATLAB R2021a rejects certain short UTF-8 struct strings emitted by SciPy's
# v5 MAT writer. Finalize countries through native jsondecode/save below.
savemat(ROOT / "world_geodata.mat", output, do_compression=True)
(ROOT / "countries_superset.json").write_text(json.dumps({"selectionPending":True,"recommended197Iso3":sorted(recommended),"countries":rows},ensure_ascii=False,indent=2)+"\n",encoding="utf8")
with (ROOT / "countries_superset.csv").open("w",encoding="utf-8-sig",newline="") as handle:
    writer=csv.DictWriter(handle,fieldnames=list(rows[0])); writer.writeheader(); writer.writerows(rows)
assert len({r["iso3"] for r in rows}) == len(rows)
assert all(-90 <= r["latitude"] <= 90 and -180 <= r["longitude"] <= 180 for r in rows)
assert len(recommended) == 197
finite = np.isfinite(all_lat[:,0]) & np.isfinite(all_lon[:,0])
print(json.dumps({"capitals":len(rows),"recommended":len(recommended),"unMembers":sum(r['unMember'] for r in rows),"boundaryFeatures":len(boundaries),"boundaryPoints":int(finite.sum()),"maxLatSegment":float(np.nanmax(np.abs(np.diff(all_lat[:,0])))),"maxLonSegment":float(np.nanmax(np.abs(np.diff(all_lon[:,0]))))},indent=2))
print("Now run MATLAB: addpath('tools'); finalize_geodata")
