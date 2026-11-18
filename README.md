# BRAINROT NUSANTARA

[![make.fun · roblox-brainrot-01](https://make.fun/badge/roblox-brainrot-01.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![rank](https://make.fun/badge/roblox-brainrot-01/dillahhhh/roblox-brainrot-01-entry-v3/rank.svg)](https://make.fun/bounty/roblox-brainrot-01/leaderboard?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)
[![reward](https://make.fun/badge/roblox-brainrot-01/dillahhhh/roblox-brainrot-01-entry-v3/reward.svg)](https://make.fun/bounty/roblox-brainrot-01?utm_source=github&utm_medium=readme&utm_campaign=roblox-brainrot-01)

A 3D brainrot game for the [roblox-brainrot-01 bounty](https://make.fun/bounty/roblox-brainrot-01) on make.fun: a Steal-a-Brainrot loop in an Indonesian night market (pasar malam) at night, lit by lamps.

Brainrots parade across a central conveyor — Ayam Ikan, Babi Terbang, Anjing Es Teh, Kucing Rendang, Beruang Durian, Harimau Api, Gajah Gamelan — you buy one, carry it home, and place it on your base where it earns $/s across 7 rarity tiers (Common → Ultra Rare). Lock your base with glass walls, steal brainrots from other players' pedestals, and rebirth to multiply your income.

The signature twist is **Pasar Tumpah**: every 3 minutes a flood wave sweeps the plaza, reroutes the conveyor, and washes unsecured brainrots away as loot crates in a scramble zone. What is already placed on your base is safe; everything on the conveyor or in your arms can wash away — and anyone brave enough to leave base after the wave can grab the crates.

## Status

FIXED29 (18 Nov 2026): steal, glass lock, rebirth, DataStore persistence (money, rebirths, slots and the carried brainrot survive rejoin), Pasar Tumpah flood with guaranteed loot crates, a mobile-responsive HUD, and the flood banner pinned to the top of the screen. The live place is "Brainrot Anomali Nusantara" (Public, 16+).

## Layout

- `main.ts` (Node 22, standard library only) hands the game in: it copies `game.rbxl`, `src/`, `screenshots/` and `PLAY.json` to `/output`, leaving out every name that starts with a dot, and writes `/output/dossier.json` with `vendor/makefun-roblox.ts`, the kit's copy, unchanged.
- `game.rbxl` is the place built from `src/` (the two scripts are the whole game; the map itself is built at runtime by the server script). Never run Rojo over a place saved from Studio.
- `src/server/` — `Main.server.luau`: the whole server — map, conveyor, bases, economy, steal, lock, rebirth, flood event, DataStore saves.
- `src/client/` — `GameUI.client.luau`: the whole client — HUD, money/carry/lock/rebirth buttons, BGM + mute, sprint, flood banner, steal prompts.
- `screenshots/` holds 4 captures of the game running (1280×720, ≤256 KiB each); the first is the game's cover thumbnail on Roblox.
- `PLAY.json` names the published place.

Run it as the grader does, writing `out/` in place of `/output`:

    mkdir -p out && MAKEFUN_OUTPUT_DIR=out node main.ts

The rules are on the bounty's page (https://make.fun/bounty/roblox-brainrot-01) and in the kit's RULES.txt, which gives every command in order (Before you submit, then Enter).
