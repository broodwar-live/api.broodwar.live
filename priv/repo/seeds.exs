# Development-only seeds.
#
# Deliberately minimal: no players, ratings, matches, builds or streams.
# Those must come from real sources (Liquipedia ingestion, admin-linked
# replays) so nothing fabricated can leak into stats. Real data:
#
#     mix broodwar.seed --players
#     mix broodwar.ingest_matches --tournament "AfreecaTV/StarCraft League Remastered/17"
#
# Maps are created automatically by match ingestion; the few below just
# give a fresh dev database something to list.

if Mix.env() == :prod do
  raise "priv/repo/seeds.exs is for development only"
end

alias Broodwar.Maps.Map, as: GameMap
alias Broodwar.Repo

maps = ["Fighting Spirit", "Circuit Breaker", "Polypoid", "Eclipse"]

for name <- maps do
  Repo.insert!(GameMap.changeset(%GameMap{}, %{name: name}),
    on_conflict: :nothing,
    conflict_target: :name
  )
end

IO.puts("Seeded #{length(maps)} maps (dev only).")
