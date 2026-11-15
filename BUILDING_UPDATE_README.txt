BUILD SYSTEM UPDATE — BASED ON ORIGINAL Gpt_v15

This update preserves the original cabin placement workflow from Gpt_v15:
- Tap Build, then tap Cabin.
- A translucent cabin blueprint appears in front of the player and follows the player's position/rotation while choosing a spot.
- Tap the on-screen Enter/Exit interaction button (or press E on keyboard) to confirm the blueprint location.
- The placed cabin blueprint becomes a construction site. Carry logs to it and interact to add them one at a time; cabin needs 10 logs.

Added Farm Fence using the same placement flow:
- Build > Farm Fence shows a translucent fence preview in front of the player.
- Move/turn the player to choose its location and direction.
- Confirm with the same Enter/Exit button / E key.
- Carry logs to the placed fence blueprint and interact to contribute them; each fence segment needs 2 logs.
- Completed segments have two horizontal farm-style rails and end posts.
- Fence segments can snap end-to-end to nearby completed fence segments.

Build button is positioned at the top centre. The cabin blueprint geometry and original cabin construction script are retained from the supplied Gpt_v15.zip.

Runtime note: Godot was not available in this environment for in-engine play testing. Please test the project in Godot after extracting the ZIP.
