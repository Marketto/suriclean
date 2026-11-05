#!/usr/bin/env python3
"""Writes TERMS.md, PRIVACY.md and THIRD-PARTY.md (Italian + English) from the app's own texts in i18n/,
so the documents in the repo are always the same the apps show."""
import json, os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UPDATED = open(os.path.join(root, "legal", "VERSION")).read().strip()
def load(c):
    p = os.path.join(root, "i18n", c + ".json")
    return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else None
def doc(kind):
    parts = []
    for code, head in (("it", "Italiano"), ("en", "English")):
        d = load(code)
        if not d or f"legal.{kind}.title" not in d: continue
        out = [f"# {d[f'legal.{kind}.title']}", "", f"_{d['legal.updated'].replace('{0}', UPDATED)}_", ""]
        i = 1
        while f"legal.{kind}.s{i}.title" in d:
            out += [f"## {d[f'legal.{kind}.s{i}.title']}", "", d[f"legal.{kind}.s{i}.body"].replace("• ", "- "), ""]
            i += 1
        parts.append("\n".join(out))
    return "\n---\n\n".join(parts) + "\n"
for kind, name in (("terms", "TERMS.md"), ("privacy", "PRIVACY.md")):
    open(os.path.join(root, name), "w", encoding="utf-8").write(doc(kind))
tp = json.load(open(os.path.join(root, "legal", "third-party.json"), encoding="utf-8"))
lines = ["# Third-party software / Software di terze parti", "",
         "SuriClean © 2026 Marco Ricupero, MIT License (see LICENSE). It bundles the following components;",
         "full license texts are in `legal/licenses/`.", "",
         "| Component | Author | License | Platforms |", "|---|---|---|---|"]
for e in tp:
    lines.append(f"| [{e['name']}]({e['url']}) | {e['by']} | {e['license']} | {', '.join(e['platforms'])} |")
lines += ["", "The complete list of Rust crates in the Windows/Ubuntu app is generated at build time",
          "(`scripts/rust-licenses.py`) and shown in the app under «Licenses»."]
open(os.path.join(root, "THIRD-PARTY.md"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("TERMS.md, PRIVACY.md, THIRD-PARTY.md written")
