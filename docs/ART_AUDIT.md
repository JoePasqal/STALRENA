# Аудит поставок графики

Автоматическая проверка файлов по manifest и контракту (`tools/art_audit.py`). Это проверка форматов, не художественная оценка и не проверка на устройстве.

| ID | Вид | Файл | Режим | Результат |
|---|---|---|---|---|
| `hero.body` | actor_atlas | atlas 1536x1024 | RGBA | ок |
| `armor.light` | armor_overlay | 768x256 | RGBA | ок |
| `icon.armor.light` | icon | 256x256 | RGBA | ок |
| `armor.field` | armor_overlay | 768x256 | RGBA | ок |
| `icon.armor.field` | icon | 256x256 | RGBA | ок |
| `armor.heavy` | armor_overlay | 768x256 | RGBA | ок |
| `icon.armor.heavy` | icon | 256x256 | RGBA | ок |
| `weapon.pistol` | weapon_sprite | 256x128 | RGBA | ок |
| `icon.weapon.pistol` | icon | 256x256 | RGBA | ок |
| `weapon.smg` | weapon_sprite | 256x128 | RGBA | ок |
| `icon.weapon.smg` | icon | 256x256 | RGBA | ок |
| `weapon.carbine` | weapon_sprite | 256x128 | RGBA | ок |
| `icon.weapon.carbine` | icon | 256x256 | RGBA | ок |
| `weapon.shotgun` | weapon_sprite | 256x128 | RGBA | ок |
| `icon.weapon.shotgun` | icon | 256x256 | RGBA | ок |
| `weapon.lmg` | weapon_sprite | 256x128 | RGBA | ок |
| `icon.weapon.lmg` | icon | 256x256 | RGBA | ок |
| `weapon.marksman` | weapon_sprite | 256x128 | RGBA | ок |
| `icon.weapon.marksman` | icon | 256x256 | RGBA | ок |
| `weapon.flamethrower` | weapon_sprite | 256x128 | RGBA | ок |
| `icon.weapon.flamethrower` | icon | 256x256 | RGBA | ок |
| `icon.module.amplifier` | icon | 256x256 | RGBA | ок |
| `icon.module.feeder` | icon | 256x256 | RGBA | ок |
| `icon.module.bolt_drive` | icon | 256x256 | RGBA | ок |
| `icon.module.target_sensor` | icon | 256x256 | RGBA | ок |
| `icon.module.precision_core` | icon | 256x256 | RGBA | ок |
| `icon.module.accelerator` | icon | 256x256 | RGBA | ок |
| `icon.module.reserve_cells` | icon | 256x256 | RGBA | ок |
| `icon.module.shock_lining` | icon | 256x256 | RGBA | ок |
| `icon.module.cell_matrix` | icon | 256x256 | RGBA | ок |
| `icon.module.servos` | icon | 256x256 | RGBA | ок |
| `icon.module.rangefinder` | icon | 256x256 | RGBA | ок |
| `icon.module.extended_mag` | icon | 256x256 | RGBA | ок |
| `enemy.drifter` | actor_atlas | strip3 768x256 | RGBA | ок |
| `enemy.runner` | actor_atlas | strip3 768x256 | RGBA | ок |
| `enemy.charger` | actor_atlas | strip3 768x256 | RGBA | ок |
| `enemy.spitter` | actor_atlas | strip3 768x256 | RGBA | ок |
| `enemy.gunner` | actor_atlas | strip3 768x256 | RGBA | ок |
| `enemy.brute` | actor_atlas | strip3 768x256 | RGBA | ок |
| `enemy.flanker` | actor_atlas | strip3 768x256 | RGBA | ок |
| `enemy.carrier` | actor_atlas | strip3 768x256 | RGBA | ок |
| `boss.cleaver` | boss_atlas | strip3 1536x512 | RGBA | ок |
| `boss.boilermaster` | boss_atlas | strip3 1536x512 | RGBA | ок |
| `boss.broodmother` | boss_atlas | strip3 1536x512 | RGBA | ок |
| `floor.sawmill` | floor_texture | 512x512 | RGBA | ок |
| `floor.pumping` | floor_texture | 512x512 | RGBA | ок |
| `floor.flooded` | floor_texture | 512x512 | RGBA | ок |
| `prop.crate` | prop | 256x256 | RGBA | ок |
| `prop.log_stack` | prop | 256x256 | RGBA | ок |
| `prop.concrete_block` | prop | 256x256 | RGBA | ок |
| `prop.fence` | prop | 256x256 | RGBA | ок |
| `prop.pipe` | prop | 256x256 | RGBA | ок |
| `prop.steam_valve` | prop | 256x256 | RGBA | ок |
| `prop.wrecked_car` | prop | 256x256 | RGBA | ок |
| `prop.reeds` | prop | 256x256 | RGBA | ок |
| `icon.medkit` | icon | 256x256 | RGBA | ок |
| `icon.parts` | icon | 256x256 | RGBA | ок |
| `fx.muzzle` | fx_atlas | 128x128 | RGBA | ок |
| `icon.bonus.double_damage` | нет файла |  |  | заглушка |
| `icon.bonus.sturdy_body` | нет файла |  |  | заглушка |
| `icon.bonus.gold_vein` | нет файла |  |  | заглушка |
| `icon.bonus.rapid_fire` | нет файла |  |  | заглушка |
| `icon.bonus.quick_legs` | нет файла |  |  | заглушка |
| `icon.bonus.sharp_eye` | нет файла |  |  | заглушка |
| `icon.bonus.fast_hands` | нет файла |  |  | заглушка |
| `ui.bonus_card_back` | нет файла |  |  | заглушка |
| `ui.bonus_case_closed` | нет файла |  |  | заглушка |
| `ui.bonus_case_open` | нет файла |  |  | заглушка |
| `icon.debuff.slow_legs` | нет файла |  |  | заглушка |
| `icon.debuff.weak_medkit` | нет файла |  |  | заглушка |
| `icon.debuff.molotov` | нет файла |  |  | заглушка |
| `icon.debuff.dull_ammo` | нет файла |  |  | заглушка |
| `icon.debuff.frail` | нет файла |  |  | заглушка |
| `icon.debuff.stiff_bolt` | нет файла |  |  | заглушка |
| `icon.debuff.poor_loot` | нет файла |  |  | заглушка |
| `ui.curse_card_back` | нет файла |  |  | заглушка |
| `ui.curse_case_closed` | нет файла |  |  | заглушка |
| `ui.curse_case_open` | нет файла |  |  | заглушка |
| `prop.concrete_block_b` | нет файла |  |  | заглушка |
| `prop.concrete_block_c` | нет файла |  |  | заглушка |
| `prop.pipe_long` | нет файла |  |  | заглушка |
| `prop.pipe_tee` | нет файла |  |  | заглушка |
| `prop.wrecked_car_b` | нет файла |  |  | заглушка |
| `prop.wrecked_car_c` | нет файла |  |  | заглушка |
| `prop.machine_a` | нет файла |  |  | заглушка |
| `prop.machine_b` | нет файла |  |  | заглушка |
| `prop.pillar` | нет файла |  |  | заглушка |
| `water.flooded` | нет файла |  |  | заглушка |
| `decor.sawmill.sawdust_pile` | нет файла |  |  | заглушка |
| `decor.sawmill.stump` | нет файла |  |  | заглушка |
| `decor.sawmill.planks` | нет файла |  |  | заглушка |
| `decor.sawmill.barrel` | нет файла |  |  | заглушка |
| `decor.sawmill.chain` | нет файла |  |  | заглушка |
| `decor.sawmill.tire` | нет файла |  |  | заглушка |
| `decor.sawmill.forklift` | нет файла |  |  | заглушка |
| `decor.sawmill.saw_machine` | нет файла |  |  | заглушка |
| `decor.sawmill.fire_barrel` | нет файла |  |  | заглушка |
| `decor.sawmill.oil_stain` | нет файла |  |  | заглушка |
| `decor.pumping.cable_reel` | нет файла |  |  | заглушка |
| `decor.pumping.rust_barrel` | нет файла |  |  | заглушка |
| `decor.pumping.oil_puddle` | нет файла |  |  | заглушка |
| `decor.pumping.panel_a` | нет файла |  |  | заглушка |
| `decor.pumping.panel_b` | нет файла |  |  | заглушка |
| `decor.pumping.barrier` | нет файла |  |  | заглушка |
| `decor.pumping.grate` | нет файла |  |  | заглушка |
| `decor.pumping.lamp_post` | нет файла |  |  | заглушка |
| `decor.flooded.driftwood` | нет файла |  |  | заглушка |
| `decor.flooded.dead_tree` | нет файла |  |  | заглушка |
| `decor.flooded.sandbags` | нет файла |  |  | заглушка |
| `decor.flooded.rocks` | нет файла |  |  | заглушка |
| `decor.flooded.algae` | нет файла |  |  | заглушка |
| `decor.flooded.float_debris` | нет файла |  |  | заглушка |
| `decor.flooded.fence_broken` | нет файла |  |  | заглушка |
| `decor.flooded.grass_island` | нет файла |  |  | заглушка |
| `decor.common.bones` | нет файла |  |  | заглушка |
| `decor.common.blood_stain` | нет файла |  |  | заглушка |
| `decor.common.shells` | нет файла |  |  | заглушка |
| `decor.common.rags` | нет файла |  |  | заглушка |
| `decor.common.weeds` | нет файла |  |  | заглушка |
| `decor.common.backpack` | нет файла |  |  | заглушка |
| `corpse.drifter` | нет файла |  |  | заглушка |
| `corpse.runner` | нет файла |  |  | заглушка |
| `corpse.charger` | нет файла |  |  | заглушка |
| `corpse.spitter` | нет файла |  |  | заглушка |
| `corpse.gunner` | нет файла |  |  | заглушка |
| `corpse.brute` | нет файла |  |  | заглушка |
| `corpse.flanker` | нет файла |  |  | заглушка |
| `corpse.carrier` | нет файла |  |  | заглушка |
| `corpse.boss.cleaver` | нет файла |  |  | заглушка |
| `corpse.boss.boilermaster` | нет файла |  |  | заглушка |
| `corpse.boss.broodmother` | нет файла |  |  | заглушка |
| `enemy.drifter.walk` | нет файла |  |  | заглушка |
| `enemy.drifter.attack` | нет файла |  |  | заглушка |
| `enemy.drifter.death` | нет файла |  |  | заглушка |
| `enemy.runner.walk` | нет файла |  |  | заглушка |
| `enemy.runner.attack` | нет файла |  |  | заглушка |
| `enemy.runner.death` | нет файла |  |  | заглушка |
| `enemy.charger.walk` | нет файла |  |  | заглушка |
| `enemy.charger.attack` | нет файла |  |  | заглушка |
| `enemy.charger.death` | нет файла |  |  | заглушка |
| `enemy.spitter.walk` | нет файла |  |  | заглушка |
| `enemy.spitter.attack` | нет файла |  |  | заглушка |
| `enemy.spitter.death` | нет файла |  |  | заглушка |
| `enemy.gunner.walk` | нет файла |  |  | заглушка |
| `enemy.gunner.attack` | нет файла |  |  | заглушка |
| `enemy.gunner.death` | нет файла |  |  | заглушка |
| `enemy.brute.walk` | нет файла |  |  | заглушка |
| `enemy.brute.attack` | нет файла |  |  | заглушка |
| `enemy.brute.death` | нет файла |  |  | заглушка |
| `enemy.flanker.walk` | нет файла |  |  | заглушка |
| `enemy.flanker.attack` | нет файла |  |  | заглушка |
| `enemy.flanker.death` | нет файла |  |  | заглушка |
| `enemy.carrier.walk` | нет файла |  |  | заглушка |
| `enemy.carrier.attack` | нет файла |  |  | заглушка |
| `enemy.carrier.death` | нет файла |  |  | заглушка |
| `boss.cleaver.walk` | нет файла |  |  | заглушка |
| `boss.cleaver.death` | нет файла |  |  | заглушка |
| `boss.boilermaster.walk` | нет файла |  |  | заглушка |
| `boss.boilermaster.death` | нет файла |  |  | заглушка |
| `boss.broodmother.walk` | нет файла |  |  | заглушка |
| `boss.broodmother.death` | нет файла |  |  | заглушка |
| `armor.light.anim` | нет файла |  |  | заглушка |
| `armor.field.anim` | нет файла |  |  | заглушка |
| `armor.heavy.anim` | нет файла |  |  | заглушка |
| `ui.card_flip_buff` | нет файла |  |  | заглушка |
| `ui.card_flip_curse` | нет файла |  |  | заглушка |
| `ui.card_face_buff` | нет файла |  |  | заглушка |
| `ui.card_face_curse` | нет файла |  |  | заглушка |
| `ui.card_glow` | нет файла |  |  | заглушка |
| `ui.bonus_case_anim` | нет файла |  |  | заглушка |
| `ui.curse_case_anim` | нет файла |  |  | заглушка |
| `fx.fire_loop` | нет файла |  |  | заглушка |
| `fx.fire_burst` | нет файла |  |  | заглушка |
| `fx.steam_puff` | нет файла |  |  | заглушка |
| `fx.explosion` | нет файла |  |  | заглушка |
| `fx.hit_spark` | нет файла |  |  | заглушка |
| `fx.heal` | нет файла |  |  | заглушка |
| `fx.spawn_ring` | нет файла |  |  | заглушка |
| `ui.logo` | нет файла |  |  | заглушка |
| `ui.menu_bg` | нет файла |  |  | заглушка |
| `app.icon` | нет файла |  |  | заглушка |
| `ui.coin` | нет файла |  |  | заглушка |

Итого записей: 182; файлов найдено: 58; с замечаниями: 0.
