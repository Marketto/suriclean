#!/usr/bin/env python3
"""Builds i18n/it.json from the per-platform sources and checks every translation against it."""
import glob, json, os, re, sys
here = os.path.dirname(os.path.abspath(__file__))
base = {}
for f in sorted(glob.glob(os.path.join(here, "src", "*.it.json"))):
    base.update(json.load(open(f, encoding="utf-8")))
json.dump(dict(sorted(base.items())), open(os.path.join(here, "it.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
ph = re.compile(r"\{\d+\}")
bad = 0
for code in [l["code"] for l in json.load(open(os.path.join(here, "languages.json"), encoding="utf-8"))]:
    p = os.path.join(here, code + ".json")
    if code == "it" or not os.path.exists(p):
        continue
    tr = json.load(open(p, encoding="utf-8"))
    missing = [k for k in base if k not in tr]
    wrong = [k for k in base if k in tr and sorted(ph.findall(tr[k])) != sorted(ph.findall(base[k]))]
    if missing or wrong:
        bad += 1
        print(f"{code}: {len(missing)} mancanti, {len(wrong)} segnaposto sbagliati", missing[:3], wrong[:3])
print(f"{len(base)} chiavi in it.json")
sys.exit(1 if bad and "--strict" in sys.argv else 0)
