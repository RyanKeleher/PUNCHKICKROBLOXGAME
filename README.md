# Punch Kick (working title)

An original Roblox fighting simulator. Punch and kick training targets to earn XP and coins, level up, spend stat points, unlock new moves, buy cosmetics, rebirth for permanent bonuses, and brawl other players in the arena. Hits send things flying with ragdoll physics.

Everything is **server-authoritative**. The client only says "I used move X facing this way". The server checks ownership, cooldowns, position and zone rules, and works out what was hit.

## Features

| System | What it does | Where |
|---|---|---|
| Combat | Hold-to-punch plus 4 move slots. 8 moves: Punch, Front Kick, Uppercut, Roundhouse (AoE), Dropkick (dash), Ground Pound (AoE), Mega Punch, Cyclone Kick. Server-side hitboxes, cooldowns, knockback | `CombatService`, `Config/Moves` |
| Ragdoll | Players ragdoll when hit by big moves; dummies ragdoll and fly when knocked out; bodies ragdoll on death | `RagdollService`, `RagdollClient` |
| Animations | Procedural keyframe poses (no uploaded assets needed). Put your own `animationId` in `Config/Moves` to use real animations | `PoseAnimator` |
| Progression | Levels 1–150, XP curve, 2 stat points per level, Power / Agility / Vitality, hit-streak XP bonus | `StatsService`, `Progression` |
| Rebirth | At level 30+: reset level and stats for +25% XP and coins forever. Cost grows each time | `StatsService`, `Config/GameConfig` |
| World | 5 floating zones linked by bridges: Starter Gym, Brawl Arena (PvP), Mountain Dojo (Lv 8), Neon Rooftop (Lv 18), Volcano Crater (Lv 30, boss). Level gates are enforced by the server | `ZoneService`, `Config/Zones` |
| Targets | 8 target types from punching bags to a 60k-HP Lava Golem boss. HP bars, respawns, rewards | `TargetService`, `Config/Targets` |
| PvP | Only inside the arena. Spawn protection, KO credit to the last hitter, KO feed | `CombatService` |
| Shop | Unlock moves, equip them into slots; 17 cosmetics (auras, trails, gloves, titles), some locked behind rebirths | `ShopService`, `CosmeticService`, `Config/Cosmetics` |
| Daily reward | Coins every 20 hours, scaled by level and rebirths | `ShopService` |
| Saving | DataStore with session locking, `UpdateAsync` only, retries with backoff, autosave, BindToClose, schema migrations | `DataService` |
| Leaderboard | Global top 10 (OrderedDataStore) on a board in the gym, plus in-server `leaderstats` | `LeaderboardService` |
| UI | HUD (level, XP, coins, move bar with cooldowns, toasts, zone banner, streak, KO feed) and menu (Stats / Moves / Shop / Rebirth) | `HUD`, `MenuUI` |
| Effects | Damage numbers, sparks, shockwaves, camera shake, target wobble, sounds (all pooled) | `EffectsController` |
| Dev tools | Studio-only chat commands and self-tests on Play | `DevService`, `Dev/ProgressionTests` |

All visuals are plain parts built in code: no imported models, meshes or images.

## Setup

### 1. Studio settings (do these once in your place)

- **Game Settings → Avatar → Avatar Type: R15.** The punch/kick poses are written for R15. R6 works, with only shoulders and hips animated.
- **Game Settings → Security → Enable Studio Access to API Services.** Without it, saving and the leaderboard are disabled in Studio. The game still runs, but you'll get a warning toast.
- **Workspace → StreamingEnabled = true** (recommended for performance).
- Use a **Baseplate** template. The world floats at Y=100 above it, and anyone who falls is put back automatically.

### 2. Get the code into Studio

**Option A: Rojo (recommended).** Install [Rokit](https://github.com/rojo-rbx/rokit), then:

```bash
rokit install
```

```bash
rojo serve
```

In Studio, open the Rojo plugin and click **Connect**.

**Option B: manual.** Create the instances below and paste each file in.
`*.server.luau` = **Script**, `*.client.luau` = **LocalScript**, everything else = **ModuleScript**.
The instance name is the file name without the extension.

| Repo folder | Studio location |
|---|---|
| `src/shared/` | `ReplicatedStorage/Shared` (Folder) |
| `src/shared/Config/` | `ReplicatedStorage/Shared/Config` (Folder): GameConfig, Moves, Targets, Zones, Cosmetics |
| `src/shared/Util/` | `ReplicatedStorage/Shared/Util` (Folder): Signal, Format |
| `src/shared/Progression.luau`, `Remotes.luau` | `ReplicatedStorage/Shared` |
| `src/server/` | `ServerScriptService/Server` (Folder); `Main` is the only Script |
| `src/server/Services/` | `ServerScriptService/Server/Services` (Folder) |
| `src/server/Util/` | `ServerScriptService/Server/Util` (Folder) |
| `src/server/Dev/` | `ServerScriptService/Server/Dev` (Folder) |
| `src/client/` | `StarterPlayer/StarterPlayerScripts/Client` (Folder); `ClientMain` is the only LocalScript |
| `src/client/Controllers/`, `src/client/UI/` | folders inside `Client` |

## Controls

| Action | PC | Controller | Mobile |
|---|---|---|---|
| Punch (hold to keep punching) | Left mouse | R2 | PUNCH button |
| Move slots 1–4 | 1–4 or Q / E / R / F | X / Y / B / R1 | tap the slot on the move bar |
| Menu | M or MENU button | Select or D-pad Up | MENU button |

Attacks go where the camera is looking.

## Testing checklist

1. **Press Play.** The Output window should show `[ProgressionTests] 8/8 passed`, the `[DevService]` line, and `[PunchKick] Server started`.
2. **Gym:** punch a bag (5 punches at level 1). You should see damage numbers, sparks, the bag wobbling, then flying off and respawning after 4s. XP and coins go up.
3. **Streak:** keep hitting quickly. "N HIT STREAK +X% XP" appears from 3 hits.
4. **Level up:** you get a banner, a burst effect and stat points. Open the menu (M) → Stats → spend points. Max health and walk speed change right away.
5. **Moves:** type `!coins 50000` and `!level 40` in chat, then Menu → Moves → unlock everything and assign slots 1–4. Try each one: Roundhouse and Ground Pound hit all around you, Dropkick lunges, Uppercut launches.
6. **Gates:** reset with `!reset`, then walk to the Dojo bridge. The gate is solid, and if you get past it you're teleported back with a message. After `!level 8` the gate opens.
7. **Shop:** buy gloves, a trail, an aura and a title. They show on your character and name tag, and Equip/Unequip toggles them.
8. **Rebirth:** at level 30 with enough coins, use Menu → Rebirth. You go back to level 1, gain a ★ on your tag, and keep your moves.
9. **PvP (Test → Clients and Servers → 2 players):** both walk into the Brawl Arena. Hits deal damage, kicks ragdoll the other player and they stand back up, a KO shows in the feed and pays coins. Outside the arena you can't hurt each other.
10. **Saving:** with API access on, earn coins, stop, Play again. The coins should still be there.
11. **Exploit sanity:** from a client command bar, run `game.ReplicatedStorage.Remotes.Attack:FireServer("megapunch", Vector3.new(0,0,-1))` without owning it. Nothing happens. Spamming `Attack` faster than the cooldown is ignored.

Dev chat commands (Studio only): `!coins N`, `!level N`, `!xp N`, `!points N`, `!rebirths N`, `!unlockall`, `!reset`.

## Architecture

- **One entry point per side.** `Server/Main` and `Client/ClientMain` start every module in a fixed order. That means no script races, and `DataService.start()` runs last so every `ProfileLoaded` listener is already connected.
- **Data-driven.** Moves, targets, zones, cosmetics and every balance number live in `Shared/Config`. `Shared/Progression` holds the pure formulas, used by the server for real outcomes and by the client for display, so the UI always matches the server.
- **Remote safety.** Every client→server remote goes through `RemoteGuard`, which applies a per-player token-bucket rate limit and error isolation. Then `Validate` type-checks each argument (NaN, inf, wrong types, long strings).
- **Hit detection.** The server builds the hitbox from its own copy of your position, after the move's wind-up, with `GetPartBoundsInBox` / `GetPartBoundsInRadius`. The query is limited to target models and other characters (`OverlapParams` Include list).
- **Ragdolls across the network.** The server toggles Motor6D ↔ BallSocket and the replicated `Ragdolled` attribute. The owning client applies velocity and the Physics humanoid state, because a client owns its character's physics.
- **Network budget.** Profile pushes are throttled through `PlayerSync` (at most one every 0.15s per player). Effects are only sent to players within 220 studs.
- **Performance.** No per-frame server loops: zone checks run every 0.5s, autosaves every 120s. Effects are pooled. Client RenderStepped loops only run while something is animating.

## Tuning cheatsheet

- **Leveling speed:** `GameConfig.Progression.XpBase` / `XpExponent`, plus each target's `xpPerHit` / `koXp`.
- **Economy:** target `koCoins`, move `price`, cosmetic `price`, `GameConfig.Rebirth`, `GameConfig.Daily`.
- **Feel:** move `cooldown`, `damage`, `knockback`, `ragdoll`, `hitbox`, and the `pose` keyframes.
- **New zone:** add it to `Config/Zones` (axis-aligned with the zone it connects to) and add a connection.

## Next steps (ideas)

- Real animations: upload them and set each move's `animationId`.
- Sounds: swap the built-in ones in `GameConfig.Sounds` for your own.
- Monetization: game passes (x2 coins, auto-punch) and developer products. These need a `MarketplaceService.ProcessReceipt` handler with idempotent receipt tracking.
- Pets or companions, quests, and a timed boss event.
