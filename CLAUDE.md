# bob — Roblox FNAF-style multiplayer horror game

## Game summary
Players hold one of four roles in a facility over a series of nights:
- **Main Office Guard**: main cameras, doors, window flashlight. Can warn the Electrician.
- **Patient Ward Nurse**: keeps up with ward work while HR watches. Has doors, a vent, and a window.
- **Electrician**: Electrical Room. Shines a light down the Electrical Hallway and hides when charged.
- **Drug Room Guard**: keeps the Test Dummy out of the Drug Room.

Animatronics: Bear (night 3+), Bunny (1+), Weasel (2+), Wolf (1+), Fox (1+), Test Dummy (1+), HR (1+).
The full behavior spec and open assumptions are in `docs/AI_DESIGN.md`.

## Code layout (Rojo, `default.project.json`)
- `src/shared/AI/` → `ReplicatedStorage.Shared.AI`: `AIConfig` (all tuning), `MapGraph` (rooms/entrances/routes), `AIRemotes`
- `src/server/AI/` → `ServerScriptService.AI`: `Director` (night control), `GameState` (the only seam to the rest of the game), `Animatronic` (base class), `Animatronics/*` (one module per animatronic), `ModelBinder` (tags → models, waypoints), `Bootstrap.server`
- `src/client/` → `StarterPlayer.StarterPlayerScripts.AIClient`: debug event logger

## Attaching behaviors (CollectionService tags)
- Tag a Model `AI_<Kind>` (`AI_Bear`, `AI_Bunny`, `AI_Weasel`, `AI_Wolf`, `AI_Fox`, `AI_TestDummy`, `AI_HR`). Each tagged model runs its own copy of that behavior, and its Name is its AI id. A kind with no tagged model does not run.
- Tag BaseParts or Attachments `AIWaypoint` to mark where models stand. The location comes from the `Location` attribute, or the part Name if unset. An optional `Animatronic` attribute (a kind or model name) gives that animatronic its own pose.
- Tag names are defined in `AIConfig.TagPrefix` / `AIConfig.WaypointTag`.

## Conventions
- Tuning values belong in `AIConfig`, not in behavior code. Per-night values use `AIConfig.perNight`.
- Animatronics read and write game state only through `GameState`.
- New animatronic: add a config entry, a subclass in `Animatronics/`, and register it in `Director` `CLASSES` and in `AIConfig.SpawnOrder`.
- Tests: `tests/run.sh` (needs the `luau` CLI) runs the scenario tests against a mocked engine.

## Importing into Studio via MCP (not done yet)
When importing into Studio through a Roblox Studio MCP server, create each file as the instance its path maps to under the Rojo rules:
- `*.server.luau` → Script
- `*.client.luau` → LocalScript
- any other `*.luau` → ModuleScript
- directories → Folder

Instance names drop the `.server` / `.client` / `.luau` suffixes. Keep the hierarchy exactly as given in `default.project.json`, because modules require each other by path.
After the scripts are in, tag each animatronic model with `CollectionService:AddTag(model, "AI_<Kind>")`, and add an `AIWaypoint`-tagged part for every location in `MapGraph` (start rooms, path rooms, and entrance spots like `MainOffice.Window`).
