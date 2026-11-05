# Driftwood (working title)

An original multiplayer survival game for Roblox: gather, craft, build, raid, wipe.
Server-authoritative: the server validates every action, and the client only draws what the server says.

## Project layout → Roblox Studio

| Repo path | Studio location | Instance type |
|---|---|---|
| `src/shared/` | `ReplicatedStorage/Shared` (Folder) | |
| `src/shared/Config.luau` | `ReplicatedStorage/Shared/Config` | ModuleScript |
| `src/shared/ItemDefinitions.luau` | `ReplicatedStorage/Shared/ItemDefinitions` | ModuleScript |
| `src/shared/InventoryLogic.luau` | `ReplicatedStorage/Shared/InventoryLogic` | ModuleScript |
| `src/shared/Remotes.luau` | `ReplicatedStorage/Shared/Remotes` | ModuleScript |
| `src/server/` | `ServerScriptService/Server` (Folder) | |
| `src/server/Main.server.luau` | `ServerScriptService/Server/Main` | **Script** |
| `src/server/Services/InventoryService.luau` | `ServerScriptService/Server/Services/InventoryService` | ModuleScript |
| `src/server/Services/WorldItemService.luau` | `ServerScriptService/Server/Services/WorldItemService` | ModuleScript |
| `src/server/Util/RateLimiter.luau` | `ServerScriptService/Server/Util/RateLimiter` | ModuleScript |
| `src/server/Util/Validate.luau` | `ServerScriptService/Server/Util/Validate` | ModuleScript |
| `src/server/Util/CharacterUtil.luau` | `ServerScriptService/Server/Util/CharacterUtil` | ModuleScript |
| `src/server/Dev/DevSpawner.luau` | `ServerScriptService/Server/Dev/DevSpawner` | ModuleScript |
| `src/server/Dev/InventoryLogicTests.luau` | `ServerScriptService/Server/Dev/InventoryLogicTests` | ModuleScript |
| `src/client/` | `StarterPlayer/StarterPlayerScripts/Client` (Folder) | |
| `src/client/ClientMain.client.luau` | `StarterPlayer/StarterPlayerScripts/Client/ClientMain` | **LocalScript** |
| `src/client/Controllers/InventoryController.luau` | `.../Client/Controllers/InventoryController` | ModuleScript |
| `src/client/UI/InventoryView.luau` | `.../Client/UI/InventoryView` | ModuleScript |

Naming rule (Rojo convention): `*.server.luau` = Script, `*.client.luau` = LocalScript, plain `*.luau` = ModuleScript.
The instance name is the file name without those suffixes.

## Option A: Rojo (recommended)

1. Install [Rojo](https://rojo.space/docs/v7/getting-started/installation/) (CLI + Studio plugin).
2. From the repo root:

   ```bash
   rojo serve
   ```
3. In Studio, open a **Baseplate** place, open the Rojo plugin, and click **Connect**.
   The tree above appears automatically, and `Workspace.StreamingEnabled` gets turned on.

## Option B: manual copy into Studio

Create the folders and instances from the table above (right-click → Insert Object), then paste each file's contents in.
Get the Script vs LocalScript vs ModuleScript type right; a wrong type is the most common mistake.
Also set `Workspace → StreamingEnabled = true` in Properties.

## Architecture in one paragraph

There is exactly one Script (`Main`) and one LocalScript (`ClientMain`); everything else is a ModuleScript started in a known order.
`InventoryService` owns the only real copy of each inventory.
Clients send small *requests* over RemoteEvents (`InventoryMove(from, to)`), and the server type-checks, range-checks and rate-limits each one, applies it with the pure functions in `InventoryLogic`, then sends the full 30-slot snapshot back.
Dropped items are anchored parts with a ProximityPrompt; their contents live in a server-only table, so the client can't edit them.

## Controls (Phase 1)

| Action | PC | Controller | Mobile |
|---|---|---|---|
| Open/close inventory | Tab or I | Y (B closes) | BAG button |
| Select hotbar slot | 1–6, mouse wheel | LB / RB | tap slot |
| Move / merge / swap | drag | select → MOVE → select target | drag, or select → MOVE → tap target |
| Split stack in half | right-click | select → SPLIT HALF | select → SPLIT HALF |
| Drop | drag outside the UI, or DROP 1 / DROP ALL | DROP 1 / DROP ALL | drag outside, or DROP buttons |
| Pick up | E | X | tap the prompt |
