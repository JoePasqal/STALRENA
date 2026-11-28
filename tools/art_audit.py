#!/usr/bin/env python3
"""Аудит PNG-поставок по manifest/ART_CONTRACT: размеры, RGBA, прозрачные поля, опорная линия, бесшовность.
python3 tools/art_audit.py > docs/ART_AUDIT.md"""
import json, os, sys
from PIL import Image
import numpy as np

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
m = json.load(open(os.path.join(root, "assets/asset_manifest_v1.json")))
rows, problems = [], []

# метаданные партий (art_meta/*.json) уточняют раскладки: сетка «столбцы x строки», опорные точки, центр трупа
meta = {}
mdir = os.path.join(root, "assets/art_meta")
for fn in sorted(os.listdir(mdir)) if os.path.isdir(mdir) else []:
    if fn.endswith(".json"):
        try:
            meta.update(json.load(open(os.path.join(mdir, fn))).get("assets", {}))
        except Exception:
            pass

def grid_of(layout):
    """'4x3_S_E_N' -> (4, 3); '4x1_shared' -> (4, 1)"""
    try:
        c, r = layout.split("_")[0].split("x")
        return int(c), int(r)
    except Exception:
        return None

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
    mt = meta.get(a["id"], {})
    mlayout = mt.get("layout", "")
    if kind in ("actor_atlas", "boss_atlas") and grid_of(mlayout):
        # раскладка из метаданных партии 5 (ходьба 4x3, замах 3x3, смерть 4x1, боссы 4x3/4x1)
        fw, fh = mt["frame_px"]
        cols_m, rows_m = grid_of(mlayout)
        info = f"{mlayout} {w}x{h}"
        if (w, h) != (cols_m * fw, rows_m * fh): notes.append(f"размер {w}x{h} не равен {cols_m}x{rows_m} кадров {fw}x{fh}")
        pivot_y = mt["pivot_px"][1]
        for r in range(rows_m):
            for c in range(cols_m):
                cell = im.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh))
                bb = alpha_bbox(cell)
                if bb is None:
                    notes.append(f"клетка r{r}c{c}: пусто"); continue
                if mlayout.startswith("4x1_shared"):
                    pass  # смерть: фигура ложится, низ допускается выше/ниже pivot в пределах клетки
                elif abs(bb[3] - pivot_y) > 14:
                    notes.append(f"клетка r{r}c{c}: низ фигуры y={bb[3]} (pivot {pivot_y})")
                if bb[0] <= 2 or bb[2] >= fw - 2 or bb[1] <= 2 or bb[3] >= fh - 1:
                    notes.append(f"клетка r{r}c{c}: фигура касается края клетки {bb}")
    elif kind == "prop" and a["id"].startswith("corpse."):
        # труп центрирован по телу: pivot — центр тела, а не линия ног; смещение появления берётся из метаданных
        info = f"{w}x{h}"
        if [w, h] != exp: notes.append(f"manifest {exp}, файл {w}x{h}")
        bb = alpha_bbox(im)
        piv = mt.get("pivot_px", a["pivot_px"])
        if bb:
            cx, cy = (bb[0] + bb[2]) / 2, (bb[1] + bb[3]) / 2
            if abs(cx - piv[0]) > 40 or abs(cy - piv[1]) > 60: notes.append(f"центр тела ({cx:.0f},{cy:.0f}) далеко от pivot {piv}")
            if bb[0] <= 1 or bb[2] >= w - 1 or bb[1] <= 1 or bb[3] >= h - 1: notes.append("труп касается края холста")
        if "spawn_offset_from_actor_world_px" not in mt: notes.append("нет spawn_offset_from_actor_world_px")
    elif kind in ("actor_atlas", "boss_atlas"):
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
        if mlayout == "6x3_S_E_N":
            # анимированная броня: 6 столбцов (walk0..walk3, hit, пустой) x 3 строки (S, E, N), кадр 256x256
            if (w, h) != (1536, 768): notes.append(f"ожидалось 1536x768, получено {w}x{h}")
            for r in range(3):
                cell = im.crop((5 * 256, r * 256, 6 * 256, (r + 1) * 256))
                if alpha_bbox(cell) is not None: notes.append(f"столбец 5 строки {r} должен быть пустым")
        elif (w, h) != (768, 256) and (w, h) != (256, 256): notes.append("ожидалось 768x256")
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
