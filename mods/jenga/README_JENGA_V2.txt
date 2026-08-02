JENGA v0.8.20
Author: Arntorius

Runtime Twitch fallback:
- Twitch remains visible in the Gameplay mode menu.
- At the start of a run, JENGA checks whether jenga-twitch-bridge is enabled.
- If Twitch is selected but the bridge is disabled or missing, the saved mode
  is changed to Normal.
- A one-time in-game message explains the fallback.
- The connector does not need to be running for this check; only the bridge mod
  must be enabled.
- If the bridge is enabled, Twitch mode remains selected normally.

Workshop packaging:
- Upload only the jenga folder.
- GitHub Twitch users additionally install jenga-twitch-bridge and run the
  standalone connector.

All v0.8.19 menu behavior, v0.8.17 selection drop protection, v0.8.16 charge
stability, distinct vote options, rich spell cards, Awakening, stack, ghost,
locking and Progress behavior remains unchanged.
