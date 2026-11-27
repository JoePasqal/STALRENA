#!/usr/bin/env python3
"""Генератор раскладок 2400x1250 из исходных 1600x1000 (позиции масштабируются, размеры ×1.2) + доборные укрытия
с гарантированными проходами >= 130 u и свободной стартовой зоной. Детерминирован (seed). Результат проверяется
tests/test_logic.gd (связность, проходимость, стартовая зона, слоты опасностей).
python3 tools/gen_layouts.py"""
import json, random, os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src_path = os.path.join(root, "data/layouts_v1_1600.json")
dst_path = os.path.join(root, "data/layouts_v1.json")
if not os.path.exists(src_path):
    os.rename(dst_path, src_path)          # сохраняем исходные малые раскладки
src = json.load(open(src_path))
W, H = 2400, 1250
SX, SY, SZ = W / 1600.0, H / 1000.0, 1.2
START = (W / 2, H / 2)
FILL = {
    "sawmill": [("logs", 260, 70), ("logs", 220, 60), ("crate", 90, 70), ("machine", 70, 200), ("crate", 80, 80)],
    "pumping": [("concrete", 90, 160), ("pipe", 360, 50), ("concrete", 140, 70), ("pipe", 280, 50), ("concrete", 80, 220)],
    "flooded": [("debris", 120, 100), ("debris", 140, 70), ("debris", 90, 90), ("debris", 60, 160), ("debris", 150, 60)],
}

def gap(a, b):
    dx = max(a[0] - (b[0] + b[2]), b[0] - (a[0] + a[2]), 0)
    dy = max(a[1] - (b[1] + b[3]), b[1] - (a[1] + a[3]), 0)
    return (dx * dx + dy * dy) ** 0.5

out = []
for li, l in enumerate(src["layouts"]):
    rng = random.Random(1000 + li)
    loc = l["location_id"]
    walls = []
    for w in l["walls"]:
        nw, nh = round(w["w"] * SZ), round(w["h"] * SZ)
        cx, cy = (w["x"] + w["w"] / 2) * SX, (w["y"] + w["h"] / 2) * SY
        x = min(max(round(cx - nw / 2), 70), W - 70 - nw)
        y = min(max(round(cy - nh / 2), 70), H - 70 - nh)
        walls.append({"x": x, "y": y, "w": nw, "h": nh, "kind": w.get("kind", "block")})
    water = []
    for w in l.get("water", []):
        water.append({"x": round(w["x"] * SX), "y": round(w["y"] * SY), "w": round(w["w"] * SX), "h": round(w["h"] * SY)})
    target = len(walls) + 12
    guard = 0
    while len(walls) < target and guard < 4000:
        guard += 1
        kind, fw, fh = rng.choice(FILL[loc])
        if rng.random() < 0.5: fw, fh = fh, fw if kind not in ("pipe",) else fh
        fw = int(fw * rng.uniform(0.85, 1.15)); fh = int(fh * rng.uniform(0.85, 1.15))
        x = rng.randint(90, W - 90 - fw); y = rng.randint(90, H - 90 - fh)
        r = (x, y, fw, fh)
        if gap(r, (START[0] - 230, START[1] - 230, 460, 460)) < 1: continue
        if any(gap(r, (o["x"], o["y"], o["w"], o["h"])) < 140 for o in walls): continue
        if any(gap(r, (o["x"], o["y"], o["w"], o["h"])) < 40 for o in water): continue
        walls.append({"x": x, "y": y, "w": fw, "h": fh, "kind": kind})
    # слоты опасностей: 8 точек сетки вдали от стен и старта
    slots = []
    cand = [(0.18, 0.25), (0.82, 0.25), (0.18, 0.75), (0.82, 0.75), (0.5, 0.14), (0.5, 0.86), (0.33, 0.5), (0.67, 0.5)]
    for fx, fy in cand:
        p = [fx * W, fy * H]
        for _ in range(200):
            ok = all(gap((p[0] - 75, p[1] - 75, 150, 150), (o["x"], o["y"], o["w"], o["h"])) > 40 for o in walls)
            if ok and ((p[0] - START[0]) ** 2 + (p[1] - START[1]) ** 2) ** 0.5 > 300: break
            p = [fx * W + rng.uniform(-120, 120), fy * H + rng.uniform(-120, 120)]
        slots.append({"x": round(p[0]), "y": round(p[1]), "r": 75})
    out.append({"id": l["id"], "location_id": loc, "size": [W, H], "start": [round(START[0]), round(START[1])],
                "walls": walls, "water": water, "hazard_slots": slots, "notes": "сгенерировано tools/gen_layouts.py"})
json.dump({"schema_version": 2, "notes": "Раскладки 2400x1250. Стартовая зона (радиус 150) свободна; связность проверяет tests/test_logic.gd.", "layouts": out},
          open(dst_path, "w"), ensure_ascii=False, indent=1)
print("layouts:", len(out), [len(o["walls"]) for o in out])
