LAST FOREST — ONLINE (friends not on same Wi-Fi)
================================================

Option A — Automatic (UPnP)
1. Host clicks Host Game
2. Game tries UPnP to open UDP port 7777
3. Status shows "Internet IP: x.x.x.x"
4. Friends Join with that IP
5. Host starts match

If UPnP fails (common on some routers/mobile data):

Option B — ZeroTier or Hamachi (recommended, easy)
1. Everyone installs ZeroTier (zerotier.com) or Radmin VPN / Hamachi
2. Create/join the SAME virtual network
3. Host: Host Game
4. Friends: Join using host's ZeroTier/Hamachi IP (shown in that app)
5. Works across cities/countries without port forwarding

Option C — Manual port forward
1. On host router: forward UDP 7777 to the host PC
2. Friends join with host public IP (whatismyip.com on host)

Notes:
- Mobile data / CGNAT often blocks incoming joins — use Option B
- Firewall: allow LastForest / Godot on private+public networks
- Max 3 players in this version
