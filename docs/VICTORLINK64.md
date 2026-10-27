# VictorLink64 integration impact

VictorLink64 (PR #3 / its PR #20) embeds the **libGDX/Kotlin** build of VictorOps Zombies: it calls
`VictorOpsGame(Entry.Host/Client/Solo)` with its own `NetLink` / `ConnectNetLink` and `Msg.BYE`, and keeps its own copy of the Kotlin sources.

This branch replaces the game with a Godot 4 project. Impact:

- **Nothing in VictorLink64 breaks today**: it vendors its own copy, and the Kotlin sources are preserved unchanged in `legacy/libgdx/` (moved with `git mv`, history intact) for any sync script that pulls them — update the path from `core/` to `legacy/libgdx/core/`.
- **The Godot game cannot be embedded as a Kotlin class.** Options for the next milestone:
  1. Godot "Android library" (Godot 4.2+ `godot-lib` AAR) hosted in a VictorLink64 Activity, with a small Kotlin plugin bridging `Entry` and the link transport; or
  2. launch the standalone `com.victorious.zombie` APK via Intent with extras (`mode=host|client|solo`, peer address).
- The Godot co-op port (ENet LAN) is not in v1; once added, VictorLink64 can hand it a host/peer address instead of a `NetLink`.
