JENGA Standalone Twitch Connector v1.0.1
=========================================

Folder placement
----------------
The JENGA_Twitch_Connector folder is a standalone program.
It does NOT belong inside Noita/mods.

It can remain anywhere, for example:
C:\JENGA_Twitch_Connector

Only these folders belong inside Noita/mods:
- jenga
- jenga-twitch-bridge

First start
-----------
Run:
setup_and_start.bat

Enter only your Twitch login name:
arntorius

Do not enter:
- https://twitch.tv/arntorius
- #arntorius
- a display name containing spaces

The connector now performs two explicit steps:
1. Connect securely to Twitch IRC.
2. Join the configured channel.

Successful startup shows:
[JENGA] Configured Twitch channel: #arntorius
[Twitch] Secure IRC connection established: ...
[Twitch] Channel joined successfully: #arntorius
[Twitch] Listening to #arntorius
[Noita] JENGA bridge connected.

Changing the channel
--------------------
Run:
change_channel.bat

Noita setup
-----------
Enable:
- JENGA
- JENGA Twitch Bridge

Set JENGA Gameplay mode to Twitch and start a new run.

Voting starts only when JENGA opens the spell picker after a world-wand pickup.
Chat messages must contain only the option number.
