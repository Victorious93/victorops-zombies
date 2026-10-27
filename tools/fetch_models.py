#!/usr/bin/env python3
"""Download the CC0 models used by the game from poly.pizza and write assets/models/SOURCES.tsv.
Only CC0 1.0 models are accepted; anything else aborts."""
import re, sys, urllib.request, os
MODELS = {
 "zombie_a": "VlXjG0N8Eg", "zombie_b": "JoBvxIUpZP",
 "pistol": "J3i9KDQ3kt", "smg": "7ehatxr7FY", "shotgun": "ZmPTnh7njL", "rifle": "Bgvuu4CUMV",
 "lmg": "K2lXTYFSLC", "launcher": "ZKvWhvu4tV", "raygun": "DIcib0mihf", "knife": "N9bfPFP1hr",
 "grenade": "xnuUzBTsUg", "glove": "l1zv4LaA4I",
 "barrel_explosive": "1orHe0kCc1", "barrel": "ONdghDBByN", "pipes": "GB6AFkoiZb", "pipes_panel": "rzvuy93JU3",
 "crate": "3VGWnZPXmG", "debris": "WrIiMMxyEP", "papers": "MujITy1NRR", "computer": "or4LLmesjq",
 "desk": "V86Go2rlnq", "shelf": "TDgvIuorcX", "fence": "qWKhREFj7H", "police_car": "BwwnUrWGmV",
 "chest": "vXaxy7ortM", "signs": "rsZJjigt1X", "gas_tank": "RoCvKBGkoC", "bricks": "Tvlvh8AAbs",
}
out = os.path.join(os.path.dirname(__file__), "..", "assets", "models")
rows = ["file\ttitle\tauthor\tlicense\tpage\tdownload"]
for name, pid in MODELS.items():
    page = f"https://poly.pizza/m/{pid}"
    html = urllib.request.urlopen(urllib.request.Request(page, headers={"User-Agent": "Mozilla/5.0"})).read().decode()
    glb = re.search(r"https://static\.poly\.pizza/[a-f0-9-]+\.glb", html).group(0)
    lic = re.search(r'"Licence":"([^"]+)"', html).group(1)
    title = (re.search(r'"Title":"([^"]+)"', html).group(1), re.search(r'"Creator":\{"Username":"([^"]+)"', html).group(1))
    if lic != "CC0 1.0": sys.exit(f"{name}: licence {lic} not CC0")
    dst = os.path.join(out, name + ".glb")
    if not os.path.exists(dst):
        open(dst, 'wb').write(urllib.request.urlopen(urllib.request.Request(glb, headers={'User-Agent': 'Mozilla/5.0'})).read())
    rows.append(f"{name}.glb\t{title[0]}\t{title[1]}\t{lic}\t{page}\t{glb}")
    print(rows[-1])
open(os.path.join(out, "SOURCES.tsv"), "w").write("\n".join(rows) + "\n")
