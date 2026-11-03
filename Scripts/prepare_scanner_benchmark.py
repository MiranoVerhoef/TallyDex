#!/usr/bin/env python3
"""Cache a reproducible TCGdex reference index and up to 16 images per selected set."""
import concurrent.futures
import hashlib
import json
import pathlib
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "artifacts/scanner-benchmark"
OUT.mkdir(parents=True, exist_ok=True)
(OUT / "images").mkdir(exist_ok=True)
BASE = "https://api.tcgdex.net/v2/en/"


def fetch(url):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, timeout=30) as response:
                return response.read()
        except Exception:
            if attempt == 2:
                raise
            time.sleep(attempt + 1)


def cached_json(name, path):
    target = OUT / name
    if not target.exists():
        target.write_bytes(fetch(BASE + path))
    return json.loads(target.read_bytes())


sets = cached_json("sets.json", "sets")
cards = cached_json("cards.json", "cards")
sets_by_id = {s["id"]: s for s in sets}
bundled = json.loads((ROOT / "TallyDex/Resources/catalog-en.json").read_text())
known = {s["id"]: s for group in bundled["series"] for s in group["sets"]}
selected_sets = [s for s in ["base1", "base2", "neo1", "ecard1", "ex1", "ex10", "dp1", "pl1",
    "hgss1", "bw1", "bw11", "xy1", "xy12", "sm1", "sm115", "sma", "swsh1", "swsh12",
    "sv01", "sv08", "me01", "30c"] if s in sets_by_id]


def set_details(sid):
    return sid, cached_json("set-" + sid + ".json", "sets/" + sid)


with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    details = dict(pool.map(set_details, selected_sets))
references = []
for card in cards:
    sid = card["id"].rsplit("-", 1)[0]
    s = sets_by_id.get(sid, {})
    detail = details.get(sid, {})
    abbreviation = detail.get("abbreviation", {}).get("official") or known.get(sid, {}).get("abbreviation")
    references.append(dict(id=card["id"], name=card["name"], localID=card.get("localId", card["id"].rsplit("-", 1)[1]),
        setID=sid, setName=s.get("name", sid), officialCount=s.get("cardCount", {}).get("official", 0),
        codes=[v for v in [sid, abbreviation] if v], image=card.get("image"),
        releaseYear=int((detail.get("releaseDate") or known.get(sid, {}).get("releaseDate") or "0000")[:4]) or None))
(OUT / "references.json").write_text(json.dumps(references))

sample = []
for sid in selected_sets:
    available = sorted((c for c in references if c["setID"] == sid and c["image"]), key=lambda c: c["id"])
    count = min(16, len(available))
    sample.extend(available[round(i * (len(available) - 1) / max(1, count - 1))] for i in range(count))


def download(card):
    target = OUT / "images" / (card["id"] + ".webp")
    try:
        if not target.exists():
            data = fetch(card["image"] + "/high.webp")
            if len(data) < 1000:
                raise ValueError("Image too small")
            target.write_bytes(data)
        return dict(id=card["id"], image="images/" + target.name,
                    split="holdout" if int(hashlib.sha256(card["id"].encode()).hexdigest()[:8], 16) % 3 == 0 else "development")
    except Exception as error:
        return dict(id=card["id"], error=str(error))


with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results = list(pool.map(download, sample))
(OUT / "manifest.json").write_text(json.dumps(results, indent=2))
print(json.dumps(dict(references=len(references), sets=len(selected_sets), downloaded=sum("image" in x for x in results),
    failed=[x for x in results if "error" in x]), indent=2), flush=True)
