# Native Plex on macOS (optional)

If you prefer **native** Plex on macOS to use **Hardware-Accelerated Streaming (VideoToolbox)**, install Plex using the official macOS installer or Homebrew Cask, then disable the Dockerized Plex:

1. Stop/remove the Plex container:
   ```bash
   (cd services/plex && docker compose down)
   ```

2. Install native Plex:
   ```bash
   brew install --cask plex-media-server
   ```

3. Open Plex Web and enable **Settings → Transcoder → Use hardware acceleration** (requires Plex Pass).

4. Keep the **/Volumes/Media** path — point Plex Libraries there so your media stays consistent with this repo.

Launch on boot is handled by Plex’s own LaunchAgent.
