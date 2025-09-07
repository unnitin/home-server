
Docker Compose compatibility patch

This patch makes the repo work whether your system has the modern Docker Compose plugin
(`docker compose`) or the legacy binary (`docker-compose`). It adds a small shim and
updates scripts to use it.

Files included:
- scripts/_compose.sh            # NEW: compose() shim that auto-detects which command to use
- scripts/30_deploy_services.sh  # UPDATED: uses compose() shim
- diagnostics/check_docker_services.sh  # UPDATED: uses compose() shim
- scripts/80_check_updates.sh    # UPDATED: uses compose() shim
- scripts/compose_up_immich.sh   # NEW: used by launchd to start Immich with compose() shim
- launchd/io.homelab.compose.immich.plist # UPDATED: points to compose_up_immich.sh

How to apply:
1) Unzip this patch in the root of your repo (same folder that contains 'scripts/' and 'launchd/'):
   unzip docker-compose-compat-patch.zip -d .

2) Re-render and load launchd plists (to pick up the new command):
   sudo scripts/40_configure_launchd.sh

3) Redeploy Immich using the new shim:
   scripts/30_deploy_services.sh

You can test detection:
- If you have 'docker compose': it will be used.
- If you have only 'docker-compose': it will be used instead.

If neither is installed, you'll get a helpful error telling you to install Docker Desktop
or run 'brew install docker-compose'.
