LastForest - Gptv30 Performance

Performance changes:
- The 600m x 600m terrain is divided into 48m chunks (8 terrain cells per side).
- Terrain meshes and terrain collision are created only for chunks around active players.
- Tree and environment-prop instances/collisions are created only for nearby chunks; their placement data is retained so chunks can be recreated as players move.
- Chunks refresh every 0.5-0.6 seconds and keep a 3x3 neighborhood around each active player.
- Zombies beyond 85m are put to sleep; zombies beyond 120m are removed and the spawner replenishes the population.
- Nearby multiplayer players are considered when deciding which world chunks remain loaded.

No shadow settings were changed. Existing city, buildings, bunker, cabin, vehicles, and gameplay systems were retained.

Validation note: scripts were reviewed statically and the project archive was checked. Godot is not installed in the build environment, so an engine launch/device FPS test was not possible here.
