#!/usr/bin/env python3
"""Аудит PNG-поставок по manifest/ART_CONTRACT: размеры, RGBA, прозрачные поля, опорная линия, бесшовность.
python3 tools/art_audit.py > docs/ART_AUDIT.md"""
import json, os, sys
from PIL import Image
import numpy as np

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
m = json.load(open(os.path.join(root, "assets/asset_manifest_v1.json")))
rows, problems = [], []

def alpha_bbox(im):
    return im.getchannel("A").getbbox()

for a in m["assets"]:
    path = os.path.join(root, a["target_path"].replace("res://", ""))
    if not os.path.exists(path):
        rows.append((a["id"], "нет файла", "", "", "заглушка"))
        continue
    im = Image.open(path)
    w, h = im.size
    notes = []
    exp = a["canvas_px"]
    kind = a["kind"]
    frame = a.get("frame_px")
    if kind in ("actor_atlas", "boss_atlas"):
        fw, fh = frame
        okw = w % fw == 0 and h % fh == 0
        layout = "strip3" if (w // fw == 3 and h == fh) else ("atlas" if w // fw >= 6 else "single" if (w, h) == (fw, fh) else "?")
        if not okw: notes.append(f"размер {w}x{h} не кратен кадру {fw}x{fh}")
        if layout == "?": notes.append("неизвестная раскладка")
        # опорная линия: нижняя граница фигуры в каждой клетке стоячих поз
        pivot_y = a["pivot_px"][1]
        cols = w // fw
        rows_n = h // fh
        for r in range(rows_n):
            for c in range(cols):
                cell = im.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh))
                bb = alpha_bbox(cell) if im.mode == "RGBA" else None
                if bb is None: continue
                is_death = (kind == "actor_atlas" and layout == "atlas" and r == 3)
                if not is_death and abs(bb[3] - pivot_y) > 14:
                    notes.append(f"клетка r{r}c{c}: низ фигуры y={bb[3]} (pivot {pivot_y})")
                if bb[0] <= 2 or bb[2] >= fw - 2 or bb[1] <= 2:
                    notes.append(f"клетка r{r}c{c}: фигура касается края клетки {bb}")
        info = f"{layout} {w}x{h}"
    elif kind == "armor_overlay":
        info = f"{w}x{h}"
        if (w, h) != (768, 256) and (w, h) != (256, 256): notes.append("ожидалось 768x256")
    elif kind == "weapon_sprite":
        info = f"{w}x{h}"
        if (w, h) != (256, 128): notes.append(f"ожидалось 256x128, получено {w}x{h}")
        bb = alpha_bbox(im)
        if bb and (bb[0] <= 1 or bb[2] >= w - 1): notes.append("рисунок касается края")
    elif kind == "icon":
        info = f"{w}x{h}"
        if (w, h) != (256, 256): notes.append(f"ожидалось 256x256, получено {w}x{h}")
        bb = alpha_bbox(im)
        if bb and (bb[0] < 16 or bb[1] < 16 or bb[2] > w - 16 or bb[3] > h - 16): notes.append(f"поле < 16 px: {bb}")
    elif kind == "floor_texture":
        info = f"{w}x{h}"
        if (w, h) != (512, 512): notes.append(f"ожидалось 512x512, получено {w}x{h}")
        arr = np.array(im.convert("RGB")).astype(int)
        lr = np.abs(arr[:, 0] - arr[:, -1]).mean(); tb = np.abs(arr[0] - arr[-1]).mean()
        inner = np.abs(arr[:, 100] - arr[:, 101]).mean()
        if lr > inner * 2.5 or tb > inner * 2.5: notes.append(f"шов заметен: LR={lr:.1f} TB={tb:.1f} (внутр. {inner:.1f})")
        mx = np.abs(arr[:, :256] - arr[:, 256:][:, ::-1]).mean()
        if mx < 6: notes.append(f"зеркальная симметрия по X (разность {mx:.1f})")
    elif kind == "prop":
        info = f"{w}x{h}"
        exp_c = a["canvas_px"]
        if [w, h] != exp_c: notes.append(f"manifest {exp_c}, файл {w}x{h}")
        bb = alpha_bbox(im)
        if bb and abs(bb[3] - a["pivot_px"][1]) > 12: notes.append(f"низ y={bb[3]}, pivot {a['pivot_px'][1]}")
    else:
        info = f"{w}x{h}"
        if [w, h] != exp: notes.append(f"manifest {exp}, файл {w}x{h}")
    if kind != "floor_texture" and im.mode != "RGBA": notes.append(f"режим {im.mode}, нужен RGBA")
    if notes: problems.append((a["id"], notes))
    rows.append((a["id"], kind, info, im.mode, "; ".join(notes) if notes else "ок"))

print("# Аудит поставок графики\n")
print("Автоматическая проверка файлов по manifest и контракту (`tools/art_audit.py`). Это проверка форматов, не художественная оценка и не проверка на устройстве.\n")
print("| ID | Вид | Файл | Режим | Результат |\n|---|---|---|---|---|")
for r in rows: print("| `%s` | %s | %s | %s | %s |" % r)
print(f"\nИтого записей: {len(rows)}; файлов найдено: {sum(1 for r in rows if r[1] != 'нет файла')}; с замечаниями: {len(problems)}.")
sys.exit(0)
