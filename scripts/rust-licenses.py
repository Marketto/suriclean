#!/usr/bin/env python3
"""Writes legal/rust-crates.json: every Rust crate bundled in the desktop app, with its license.
Run from the repo root after `cargo` can resolve the dependencies (CI does it before building)."""
import json, subprocess, os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
meta = json.loads(subprocess.check_output(
    ["cargo", "metadata", "--format-version", "1"], cwd=os.path.join(root, "desktop", "src-tauri")))
own = {p["id"] for p in meta["packages"] if p["source"] is None}
out = sorted(({"name": p["name"], "version": p["version"], "license": p.get("license") or "see repository",
               "url": p.get("repository") or f"https://crates.io/crates/{p['name']}"}
              for p in meta["packages"] if p["id"] not in own), key=lambda x: (x["name"], x["version"]))
json.dump(out, open(os.path.join(root, "legal", "rust-crates.json"), "w", encoding="utf-8"), indent=1)
print(f"{len(out)} crates -> legal/rust-crates.json")
