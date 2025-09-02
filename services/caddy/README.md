# Caddy Reverse Proxy (optional)

This proxy unifies Immich and Plex under **one HTTPS origin** (via Tailscale Serve).

- Browser URLs:
  - `https://<macmini>.<tailnet>.ts.net/photos` → Immich
  - `https://<macmini>.<tailnet>.ts.net/plex`   → Plex

> **Mobile apps:** keep using their native base URLs (Immich at root, Plex on 32400). The proxy mainly improves browser UX.

## Install & start

```bash
./scripts/35_install_caddy.sh
./scripts/36_enable_reverse_proxy.sh
```

To disable later:

```bash
./scripts/37_disable_reverse_proxy.sh
```


## Landing Page

The root (`/`) serves a simple landing page with links to Immich and Plex.

You can customize `services/caddy/landing.html`.  
When installed via `scripts/35_install_caddy.sh`, this will be copied into `/opt/homebrew/etc/caddy/landing.html`.


## Landing page
A small static landing page is served at the root (`/`) to help family users click through:
- `/photos` → Immich
- `/plex` → Plex
