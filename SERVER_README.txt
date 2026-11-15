LAST FOREST - ONLINE (dedicated server + voice)
===============================================
Server (Chabokan VPS, Ubuntu):
1. Export the game for Linux (Godot: Export > Linux, preset "Dedicated Server")
2. Upload the files to the VPS
3. Open UDP port 7777 in the Chabokan firewall (UDP, not TCP)
4. Run:  ./LastForestServer --headless --server

Players (Android):
1. Main Menu > Play Online
2. Type the VPS IP > Join Server (IP is remembered)
3. Players can join at any time
4. Voice: "Mic: ON/OFF" button at the top. Use headphones (no echo).

Android export (needed for voice):
- Export preset > Permissions: turn ON "Record Audio" and "Internet"

Synced between players: movement, zombies (server controlled),
shooting hits, zombie bites, loot pickup (map + city + hospital), voice.
Also synced (v34): vehicles (4 seats), player-vs-player damage, kill feed.
NOT synced yet: wood logs on the ground, doors, held-weapon look.
Max players: 8 (MAX_PLAYERS in network.gd)

Quick test without a server: Play Online > Host Game on one device,
Join Server with the host's IP on a second device (same Wi-Fi).

Server options: --no-pvp  (players cannot hurt each other)
