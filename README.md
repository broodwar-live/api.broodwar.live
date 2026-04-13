🇰🇷 [한국어](README.ko.md)

<div align="center">

<h1 align="center">
  broodwar.live
</h1>

<p align="center">
  <em>The community platform for StarCraft: Brood War competitive play.</em><br>
  <em>Player stats. Replay analysis. Build orders. Live streams.</em>
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

The unified home for the BW competitive community — think [basketball-reference.com](https://www.basketball-reference.com) for Brood War. Built with Elixir/Phoenix, Phoenix LiveView, SQLite, and Rust NIFs.

## Features

| Feature | Description |
|---------|-------------|
| **Player Profiles** | Career stats, Elo history, head-to-head records |
| **Match History** | Game results with build orders, APM, and army timelines |
| **Replay Analysis** | Upload a `.rep` and get instant breakdowns — build orders, APM curves, army composition |
| **Build Orders** | Structured, searchable database backed by pro replay evidence |
| **Balance Analytics** | Matchup winrates by map, era, and skill bracket |
| **Live Streams** | Korean stream tracking, ASL/BSL schedules |
| **Tournaments** | Tournament brackets, results, and history |
| **Wiki** | Community knowledge base for maps, strategies, and game mechanics |

## Quick Start

```bash
# Install dependencies and set up the database
mix setup

# Start the server
mix phx.server
```

Visit [localhost:4000](http://localhost:4000).

## Architecture

```
lib/
├── broodwar/                 # Domain contexts
│   ├── players.ex            # Player profiles, Elo, career stats
│   ├── matches.ex            # Match results, head-to-head records
│   ├── replays.ex            # Replay uploads, parsed data
│   ├── builds_context.ex     # Build order database
│   ├── streams.ex            # Live stream tracking
│   ├── tournaments.ex        # Tournament data
│   ├── wiki/                 # Wiki pages and content
│   ├── maps/                 # Map pool and metadata
│   └── ingestion/            # Background data sync
│       ├── liquipedia.ex     # Liquipedia scraping
│       ├── player_sync.ex    # Player data sync
│       └── tournament_sync.ex
├── broodwar_nif/             # Rust NIF bridge
│   └── replay_parser.ex      # Thin wrapper around bw-engine
├── broodwar_web/             # Web layer
│   ├── live/                 # LiveView pages
│   │   ├── players_live.ex   # Player list + search
│   │   ├── player_detail_live.ex
│   │   ├── matches_live.ex   # Match history
│   │   ├── match_detail_live.ex
│   │   ├── replay_live.ex    # Replay upload + browser
│   │   ├── replay_detail_live.ex
│   │   ├── builds_live.ex    # Build order database
│   │   ├── build_detail_live.ex
│   │   └── balance_live.ex   # Balance analytics
│   └── controllers/
│       └── api/              # JSON API
│           ├── player_controller.ex
│           ├── match_controller.ex
│           ├── replay_controller.ex
│           ├── build_controller.ex
│           ├── map_controller.ex
│           ├── balance_controller.ex
│           ├── stream_controller.ex
│           └── tournament_controller.ex
└── native/
    └── replay_parser/        # Rust NIF (via Rustler)
```

### Key Technical Decisions

- **Phoenix LiveView** for all interactive UI — no SPA, no client-side framework
- **SQLite** via `ecto_sqlite3` — single-file database, deployed alongside the app
- **Rust NIFs** via Rustler for replay parsing — delegates to [bw-engine](https://github.com/broodwar-live/bw-engine)
- **Oban** for background jobs — Liquipedia scraping, replay processing, stats aggregation
- **Req** for HTTP client

## API

Public JSON API at `/api`. See the full [API conventions](https://github.com/broodwar-live/.claude/blob/main/rules/api.md).

```
GET /api/players          # Player list with search/filter
GET /api/players/:id      # Player profile and stats
GET /api/matches          # Match history
GET /api/replays          # Replay metadata
GET /api/builds           # Build order database
GET /api/maps             # Map pool
GET /api/balance          # Matchup winrates
GET /api/streams          # Live streams
GET /api/tournaments      # Tournament data
```

## Development

### Prerequisites

- Elixir 1.18+ / Erlang OTP 27+
- Rust stable toolchain (for NIF compilation)
- Node.js (for esbuild/tailwind asset tooling)

### Commands

```bash
mix setup                 # Install deps, create DB, build assets
mix phx.server            # Start dev server
mix test                  # Run tests
mix precommit             # Compile (warnings-as-errors) + format + test
mix format                # Format code
```

### Database

SQLite with WAL mode for concurrent reads during writes. Migrations must be reversible.

```bash
mix ecto.create           # Create database
mix ecto.migrate          # Run migrations
mix ecto.reset            # Drop + recreate + seed
```

## Related Projects

- [bw-engine](https://github.com/broodwar-live/bw-engine) — Rust replay parser and game engine (NIF + WASM)
- [assets-pipeline](https://github.com/broodwar-live/assets-pipeline) — BW asset extraction tool
- [assets](https://github.com/broodwar-live/assets) — Pre-built unit sprites and icons
- [alphacraft](https://github.com/broodwar-live/alphacraft) — ML agent for competitive BW play

## Legal Disclaimer

This project is not affiliated with, endorsed by, or associated with Blizzard Entertainment, Inc. or Microsoft Corporation. "StarCraft" and "Brood War" are registered trademarks of Blizzard Entertainment, Inc. This is a free, open-source, non-commercial community project built by fans for fans.

## License

MIT
