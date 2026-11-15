MENU + STUDIO INTRO
===================

Flow:
  boot.tscn  ->  studio intro (video or splash)  ->  main_menu.tscn  ->  game

Menu buttons:
  - Play Offline  -> loads main.tscn (current singleplayer)
  - Play Online   -> placeholder (multiplayer next)
  - Settings      -> volume slider + graphics Medium/High
  - Quit

Settings are saved to user://settings.cfg

Optional studio video:
  Put your intro video at:  res://studio_intro.ogv
  (Godot works best with .ogv / Theora)
  If the file is missing, an animated text splash is shown instead.
  Tap/click/any key skips the intro.
