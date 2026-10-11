🇰🇷 [한국어](README.ko.md)

<div align="center">

<h1 align="center">
  broodwar.live
</h1>

<p align="center">
  <em>JSON API for broodwar.live — the StarCraft: Brood War community platform.</em><br>
  <em>Player stats. Replay parsing. Openings. Live streams.</em>
</p>

<p align="center">
  <a href="https://elixir-lang.org/">
    <img alt="Elixir" src="https://img.shields.io/badge/Elixir-1.18+-4B275F?logo=elixir&logoColor=white&style=for-the-badge">
  </a>
  <a href="https://www.phoenixframework.org/">
    <img alt="Phoenix" src="https://img.shields.io/badge/Phoenix-1.8-FD4F00?logo=phoenixframework&logoColor=white&style=for-the-badge">
  </a>
  <a href="https://www.sqlite.org/">
    <img alt="SQLite" src="https://img.shields.io/badge/SQLite-003B57?logo=sqlite&logoColor=white&style=for-the-badge">
  </a>
  <a href="LICENSE">
    <img alt="License" src="https://img.shields.io/badge/License-MIT-c6a0f6?style=for-the-badge">
  </a>
</p>

</div>

---

`api.broodwar.live` is the slim JSON API behind [broodwar.live](https://broodwar.live). The website itself is a Zola static site on Cloudflare Pages; it calls this API with `fetch()` for dynamic data. This repo has **no HTML, LiveView or static assets**.

What it does:

- Parses uploaded `.rep` files with a Rust NIF ([replay-core](https://github.com/broodwar-live/bw-engine) via Rustler)
- Serves players, matches, replays, openings, balance stats, tournaments and maps
- Polls live streams (Twitch, SOOP/AfreecaTV) every 3 minutes
- Syncs player and tournament data from Liquipedia (operator-run)

## API

All endpoints are under `/api` and follow the [API conventions](https://github.com/broodwar-live/.claude/blob/main/rules/api.md). Errors look like `{"error": {"code": "NOT_FOUND", "message": "..."}}`. Lists take `?page=` and `?per_page=` (default 50, max 200).

```
GET  /api/health                     # Liveness + DB check (used by Fly)
GET  /api/players                    # ?race= &status= &search=
GET  /api/players/:id
GET  /api/players/:id/matches
GET  /api/players/:id/stats          # Tournament record + replay-derived stats
GET  /api/matches                    # ?tournament_id= &matchup=
GET  /api/replays                    # Summaries only (no parsed_data)
GET  /api/replays/:id                # Full parsed replay
POST /api/replays                    # Multipart "file" upload (see below)
GET  /api/openings                   # ?race=T|P|Z &matchup=TvZ
GET  /api/builds
GET  /api/maps
GET  /api/balance
GET  /api/streams                    # ?platform= &live=true
GET  /api/tournaments[/:slug[/:season]]

POST /api/admin/replays              # Bearer ADMIN_API_KEY: upload + link + rate
POST /api/admin/replays/:id/rate     # Bearer ADMIN_API_KEY: link + rate existing
```

### Replay uploads

`POST /api/replays` is anonymous, so it is deliberately limited:

- Max 5 MiB per file (real replays are ~50–300 KB); larger → `413`
- The file must start with the `.rep` magic (`reRS`/`seRS`); otherwise → `422` without touching the parser
- 10 uploads per hour per client IP → `429` with `retry-after` (reads: 600/min per IP)
- Duplicate files (same SHA-256) return the existing replay with `200`
- Anonymous uploads **never** create players or change Elo. Linking replays to players and rating them happens only through the admin endpoints or the operator batch import (`mix broodwar.import_replays`), and at most once per replay.

### Player images

The static site hosts player photos under `https://broodwar.live/images/players/`. The API stores the path and returns an absolute `image_url`; it does not serve images itself.

## Development

Prerequisites: Elixir 1.18+ / OTP 27+, Rust stable (Rustler compiles the NIF during `mix compile`).

```bash
mix setup            # deps, create + migrate SQLite DB, seeds
mix phx.server       # http://localhost:4000/api/health
mix test
```

CI-equivalent checks:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix test
(cd native/replay_parser && cargo fmt --check && cargo clippy --all-targets -- -D warnings)
```

Data tasks:

```bash
mix broodwar.seed                        # Players + tournaments from Liquipedia
mix broodwar.import_replays <dir>        # Trusted batch import (links + rates)
```

### Replay parser NIF

`native/replay_parser` is the only Elixir binding for replay-core. It depends on `bw-engine` by pinned git `rev` (bump it deliberately with `cargo update -p replay-core` after editing `Cargo.toml`). `bw-engine/crates/replay-nif` is a separate, unused binding; its NIFs are subsets of this crate's `parse/1`.

`native/replay_parser/.cargo/config.toml` sets `git-fetch-with-cli = true` so Cargo uses the `git` CLI, which respects SSH `insteadOf` rewrites in a global git config.

### Configuration

| Env var | Purpose | Default |
|---|---|---|
| `SECRET_KEY_BASE` | Required in prod (`mix phx.gen.secret`) | — |
| `DATABASE_PATH` | SQLite file | `/data/broodwar.db` (prod) |
| `PHX_HOST` | Public host | `api.broodwar.live` |
| `ADMIN_API_KEY` | Bearer token for `/api/admin/*`; admin routes are disabled when unset | unset |
| `CLIENT_IP_HEADER` | Header with the real client IP behind the proxy | `fly-client-ip` (prod) |
| `TWITCH_CLIENT_ID` / `TWITCH_CLIENT_SECRET` | Twitch polling; skipped when unset | unset |
| `SOOP_CLIENT_ID` / `SOOP_CATEGORY` | SOOP (AfreecaTV) polling; skipped when unset | unset |
| `STATIC_SITE_URL` | Base for player image URLs | `https://broodwar.live` |

SOOP note: the old `openapi.afreecatv.com/broad/search` endpoint returns 404. SOOP's `openapi.sooplive.co.kr/broad/list` requires a `client_id` registered at [developers.sooplive.co.kr](https://developers.sooplive.co.kr), plus the StarCraft category number. Until both are set, SOOP polling is skipped. The request shape is based on SOOP's public Open API and is unverified without a key.

## Deployment (Fly.io)

The `Dockerfile` builds the NIF and an Elixir release; `fly.toml` runs one machine in `nrt` (Tokyo, the closest Fly region to Korea) with SQLite on a volume at `/data`. Migrations run automatically on boot.

```bash
# 1. Create the app without deploying (keep fly.toml; rename if broodwar-api is taken)
fly launch --no-deploy --copy-config --name broodwar-api --region nrt

# 2. Volume for SQLite (one machine only; SQLite can't be shared)
fly volumes create broodwar_data --region nrt --size 1

# 3. Secrets
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret) ADMIN_API_KEY=$(openssl rand -hex 32)
fly secrets set TWITCH_CLIENT_ID=... TWITCH_CLIENT_SECRET=...      # optional
fly secrets set SOOP_CLIENT_ID=... SOOP_CATEGORY=...               # optional

# 4. Deploy and check
fly deploy
curl https://broodwar-api.fly.dev/api/health

# 5. Custom domain
fly certs add api.broodwar.live
```

In Cloudflare DNS for `broodwar.live`, add a `CNAME` record `api` → `broodwar-api.fly.dev` set to **DNS only** (grey cloud). Fly issues the TLS certificate and sets `Fly-Client-IP`. Proxying through Cloudflare (orange cloud) would make every client look like a Cloudflare IP to the rate limiter, and needs extra certificate setup. Then run `fly certs check api.broodwar.live`.

Backups: the database is a single file on the volume. Fly takes daily volume snapshots; for off-site copies, use `sqlite3 /data/broodwar.db ".backup ..."` via `fly ssh console`.

## Related Projects

- [broodwar.live](https://github.com/broodwar-live/broodwar.live) — Zola static site (frontend)
- [bw-engine](https://github.com/broodwar-live/bw-engine) — Rust replay parser and game engine

## Legal Disclaimer

This project is not affiliated with, endorsed by, or associated with Blizzard Entertainment, Inc. or Microsoft Corporation. "StarCraft" and "Brood War" are registered trademarks of Blizzard Entertainment, Inc. This is a free, open-source, non-commercial community project built by fans for fans.

## License

MIT
