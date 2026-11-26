#!/usr/bin/env python3
"""Adds a new version to altstore/apps.json (AltStore source v2, plus legacy fields for SideStore)."""
import argparse, json, os, datetime

p = argparse.ArgumentParser()
p.add_argument("--version", required=True)
p.add_argument("--build", required=True)
p.add_argument("--url", required=True)
p.add_argument("--size", required=True, type=int)
p.add_argument("--notes", default="")
p.add_argument("--file", default=os.path.join(os.path.dirname(__file__), "..", "altstore", "apps.json"))
a = p.parse_args()

with open(a.file, encoding="utf-8") as f:
    src = json.load(f)

app = src["apps"][0]
date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
entry = {
    "version": a.version,
    "buildVersion": a.build,
    "date": date,
    "localizedDescription": a.notes.strip() or "Slowed " + a.version,
    "downloadURL": a.url,
    "size": a.size,
    "minOSVersion": "16.0",
}
versions = [v for v in app.get("versions", []) if v.get("version") != a.version]
app["versions"] = ([entry] + versions)[:15]

# Legacy single-version fields (AltStore Classic < 2.0 / SideStore)
app["version"] = a.version
app["versionDate"] = date
app["versionDescription"] = entry["localizedDescription"]
app["downloadURL"] = a.url
app["size"] = a.size

with open(a.file, "w", encoding="utf-8") as f:
    json.dump(src, f, ensure_ascii=False, indent=2)
    f.write("\n")
print("Updated", a.file, "->", a.version)
