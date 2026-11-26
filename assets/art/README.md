# Куда класть графику

Пути файлов заданы в `assets/asset_manifest_v1.json` (поле `target_path`), например
`assets/art/weapons/pistol.png`. Положите PNG (RGBA) по этому пути — `AssetRegistry`
подхватит его без правок кода, баланса и коллизий. Пока файла нет, игра рисует
процедурную заглушку того же логического размера (и один раз пишет это в диагностику).

Раскладка атласа актёра (герой/враги/боссы) по умолчанию: строки — направления `S`, `E`, `N`
(`W` зеркалируется из `E`), колонки — `idle, walk0..walk3, hit`; строка 3 — смерть (4 кадра).
Размер кадра, pivot, масштаб — из manifest. Подробности — `docs/ART_CONTRACT.md`.

Статус `prepared/integrated/verified` фиксируйте вручную в `assets/art_status.json`
(`{"weapon.pistol": "verified"}`) после проверки размера, прозрачности, pivot и ракурсов.
Отчёт: `godot --headless --path . --script res://tools/art_report.gd > docs/ART_STATUS.md`.
