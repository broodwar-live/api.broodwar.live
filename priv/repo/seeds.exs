alias Broodwar.Repo
alias Broodwar.Players.Player
alias Broodwar.Maps.Map
alias Broodwar.Tournaments.Tournament
alias Broodwar.Matches.Match
alias Broodwar.Builds.Build
alias Broodwar.Streams.Stream

import Ecto.Query

# Helper: insert if not exists (by name)
defmodule Seeds do
  def upsert!(repo, schema, attrs, conflict_field \\ :name) do
    changeset = schema.changeset(struct(schema), attrs)

    case repo.insert(changeset, on_conflict: :nothing, conflict_target: conflict_field) do
      {:ok, record} ->
        if record.id do
          record
        else
          repo.one!(from(s in schema, where: field(s, ^conflict_field) == ^attrs[conflict_field]))
        end

      {:error, changeset} ->
        raise "Seed error: #{inspect(changeset.errors)}"
    end
  end
end

IO.puts("Seeding players...")

players_data = [
  # Tier S — Elite
  %{name: "Flash", aliases: ["이영호", "Lee Young Ho"], race: "T", country: "KR", rating: 2850},
  %{name: "Rain", aliases: ["정윤종", "Jung Yoon Jong"], race: "P", country: "KR", rating: 2800},
  %{name: "Snow", aliases: ["이정훈", "Lee Jung Hoon"], race: "P", country: "KR", rating: 2790},
  %{name: "Soulkey", aliases: ["김민철", "Kim Min Chul"], race: "Z", country: "KR", rating: 2780},
  # Tier A+ — Strong contenders
  %{name: "Sharp", aliases: ["조기석", "Cho Ki Suk"], race: "T", country: "KR", rating: 2750},
  %{name: "Mini", aliases: ["변현제", "Byun Hyun Je"], race: "P", country: "KR", rating: 2740},
  %{name: "Last", aliases: ["김성현", "Kim Sung Hyun"], race: "T", country: "KR", rating: 2735},
  # Tier A — Regular Ro8
  %{name: "hero", aliases: ["김태영", "Kim Tae Young"], race: "T", country: "KR", rating: 2720},
  %{name: "Best", aliases: ["노기웅", "Noh Ki Woong"], race: "P", country: "KR", rating: 2710},
  %{name: "Light", aliases: ["이재호", "Lee Jae Ho"], race: "T", country: "KR", rating: 2700},
  %{name: "Rush", aliases: ["서명수", "Seo Myung Soo"], race: "Z", country: "KR", rating: 2690},
  %{name: "Soma", aliases: ["조기정", "Cho Ki Jung"], race: "Z", country: "KR", rating: 2685},
  %{name: "EffOrt", aliases: ["김정우", "Kim Jung Woo"], race: "Z", country: "KR", rating: 2680},
  # Tier A- — Competitive
  %{name: "JyJ", aliases: ["주윤정"], race: "P", country: "KR", rating: 2660},
  %{name: "Shuttle", aliases: ["김윤중"], race: "P", country: "KR", rating: 2650},
  %{name: "Mind", aliases: ["박세건", "Park Se Geon"], race: "T", country: "KR", rating: 2640},
  # Tier B+ — Regular qualifiers
  %{name: "Larva", aliases: ["임홍규", "Lim Hong Gyu"], race: "Z", country: "KR", rating: 2620},
  %{name: "Bisu", aliases: ["김택용", "Kim Taek Yong"], race: "P", country: "KR", rating: 2610},
  %{name: "Jaedong", aliases: ["이제동", "Lee Jae Dong"], race: "Z", country: "KR", rating: 2600},
  %{name: "Action", aliases: ["정명근"], race: "T", country: "KR", rating: 2580},
  %{name: "sSak", aliases: ["김학수"], race: "P", country: "KR", rating: 2570},
  %{name: "Mong", aliases: ["윤찬희"], race: "T", country: "KR", rating: 2560},
  %{name: "Stork", aliases: ["송병구", "Song Byung Goo"], race: "P", country: "KR", rating: 2550},
  %{name: "Calm", aliases: ["김형우"], race: "Z", country: "KR", rating: 2540},
  %{name: "Guemchi", aliases: ["김기현"], race: "Z", country: "KR", rating: 2530},
  # Notable foreign players
  %{name: "Dewalt", aliases: [], race: "Z", country: "UA", rating: 2650},
  %{name: "Sziky", aliases: [], race: "P", country: "HU", rating: 2580},
  %{name: "Scan", aliases: [], race: "T", country: "PL", rating: 2560},
  %{name: "Bonyth", aliases: [], race: "P", country: "PL", rating: 2550},
  %{name: "Trutacz", aliases: [], race: "Z", country: "PL", rating: 2520},
]

players =
  for attrs <- players_data, into: %{} do
    player = Seeds.upsert!(Repo, Player, attrs)
    {attrs.name, player}
  end

IO.puts("  #{map_size(players)} players seeded")

# ---

IO.puts("Seeding maps...")

maps_data = [
  # Current competitive pool
  %{name: "Fighting Spirit", width: 128, height: 128, tileset: "Jungle"},
  %{name: "Polypoid", width: 128, height: 128, tileset: "Twilight"},
  %{name: "Radeon", width: 128, height: 128, tileset: "Badlands"},
  %{name: "Butter", width: 128, height: 128, tileset: "Jungle"},
  %{name: "Optimizer", width: 128, height: 128, tileset: "Badlands"},
  %{name: "Sylphid", width: 128, height: 128, tileset: "Twilight"},
  %{name: "Hitchhiker", width: 128, height: 128, tileset: "Desert"},
  %{name: "Vermeer", width: 128, height: 128, tileset: "Twilight"},
  %{name: "Sparkle", width: 128, height: 128, tileset: "Twilight"},
  %{name: "Eddy", width: 128, height: 128, tileset: "Badlands"},
  # Classics
  %{name: "Circuit Breaker", width: 128, height: 128, tileset: "Space"},
  %{name: "La Mancha", width: 128, height: 128, tileset: "Desert"},
  %{name: "Eclipse", width: 128, height: 128, tileset: "Twilight"},
  %{name: "Transistor", width: 128, height: 128, tileset: "Twilight"},
  %{name: "Python", width: 128, height: 128, tileset: "Jungle"},
]

maps =
  for attrs <- maps_data, into: %{} do
    map = Seeds.upsert!(Repo, Map, attrs)
    {attrs.name, map}
  end

IO.puts("  #{map_size(maps)} maps seeded")

# ---

IO.puts("Seeding tournaments...")

tournaments_data = [
  %{name: "ASL Season 13", short_name: "ASL S13", type: "individual", year: 2023, season: 13},
  %{name: "ASL Season 14", short_name: "ASL S14", type: "individual", year: 2024, season: 14},
  %{name: "ASL Season 15", short_name: "ASL S15", type: "individual", year: 2024, season: 15},
  %{name: "ASL Season 16", short_name: "ASL S16", type: "individual", year: 2024, season: 16},
  %{name: "ASL Season 17", short_name: "ASL S17", type: "individual", year: 2025, season: 17},
  %{name: "BSL Season 17", short_name: "BSL S17", type: "individual", year: 2024, season: 17},
  %{name: "BSL Season 18", short_name: "BSL S18", type: "individual", year: 2024, season: 18},
  %{name: "BSL Season 19", short_name: "BSL S19", type: "individual", year: 2024, season: 19},
  %{name: "BSL Season 20", short_name: "BSL S20", type: "individual", year: 2025, season: 20},
]

tournaments =
  for attrs <- tournaments_data, into: %{} do
    existing = Repo.one(from(t in Tournament, where: t.name == ^attrs.name))

    tournament =
      if existing do
        existing
      else
        Repo.insert!(Tournament.changeset(%Tournament{}, attrs))
      end

    {attrs.name, tournament}
  end

IO.puts("  #{map_size(tournaments)} tournaments seeded")

# ---

IO.puts("Seeding matches...")

finals_data = [
  %{tournament: "ASL Season 13", round: "Finals",
    player_a: "Snow", race_a: "P", score_a: 4,
    player_b: "Soulkey", race_b: "Z", score_b: 2,
    played_at: ~U[2023-12-10 11:00:00Z]},
  %{tournament: "ASL Season 14", round: "Finals",
    player_a: "Soulkey", race_a: "Z", score_a: 4,
    player_b: "Snow", race_b: "P", score_b: 1,
    played_at: ~U[2024-04-14 11:00:00Z]},
  %{tournament: "ASL Season 15", round: "Finals",
    player_a: "Rain", race_a: "P", score_a: 4,
    player_b: "Flash", race_b: "T", score_b: 2,
    played_at: ~U[2024-08-11 11:00:00Z]},
  %{tournament: "ASL Season 16", round: "Finals",
    player_a: "Snow", race_a: "P", score_a: 4,
    player_b: "Rain", race_b: "P", score_b: 3,
    played_at: ~U[2024-12-08 11:00:00Z]},
  %{tournament: "BSL Season 18", round: "Finals",
    player_a: "Dewalt", race_a: "Z", score_a: 4,
    player_b: "Scan", race_b: "T", score_b: 1,
    played_at: ~U[2024-06-15 18:00:00Z]},
  %{tournament: "BSL Season 19", round: "Finals",
    player_a: "Dewalt", race_a: "Z", score_a: 4,
    player_b: "Sziky", race_b: "P", score_b: 2,
    played_at: ~U[2024-10-20 18:00:00Z]},
  %{tournament: "BSL Season 20", round: "Finals",
    player_a: "Dewalt", race_a: "Z", score_a: 4,
    player_b: "Bonyth", race_b: "P", score_b: 2,
    played_at: ~U[2025-02-16 18:00:00Z]},
]

match_count =
  Enum.reduce(finals_data, 0, fn data, count ->
    pa = players[data.player_a]
    pb = players[data.player_b]
    t = tournaments[data.tournament]

    existing =
      Repo.one(
        from(m in Match,
          where:
            m.tournament_id == ^t.id and
              m.round == ^data.round and
              m.player_a_id == ^pa.id and
              m.player_b_id == ^pb.id
        )
      )

    if existing do
      count
    else
      attrs = %{
        tournament_id: t.id,
        round: data.round,
        player_a_id: pa.id,
        player_b_id: pb.id,
        race_a: data.race_a,
        race_b: data.race_b,
        score_a: data.score_a,
        score_b: data.score_b,
        played_at: data.played_at,
        source: "seed"
      }

      Repo.insert!(Match.changeset(%Match{}, attrs))
      count + 1
    end
  end)

IO.puts("  #{match_count} matches seeded")

# ---

IO.puts("Seeding builds...")

builds_data = [
  %{name: "2 Factory Vulture", race: "T", matchup: "TvZ",
    description: "Fast expand into 2 factory vulture harass. Strong map control and transition into mech.",
    tags: ["mech", "harass", "economic"], games: 342, winrate: 56},
  %{name: "Bisu Build", race: "P", matchup: "PvZ",
    description: "Corsair into Dark Templar opening. Aggressive tech path that pressures Zerg's third.",
    tags: ["aggressive", "tech", "corsair"], games: 287, winrate: 53},
  %{name: "3 Hatch Lurker", race: "Z", matchup: "ZvT",
    description: "Economic 3 hatch opening into fast lurker tech. Defends early aggression and scales well.",
    tags: ["economic", "lurker", "defensive"], games: 256, winrate: 51},
  %{name: "1 Gate FE", race: "P", matchup: "PvT",
    description: "Single gateway expand. Standard safe opening against Terran with fast economy.",
    tags: ["standard", "economic", "safe"], games: 412, winrate: 50},
  %{name: "2 Rax Academy", race: "T", matchup: "TvP",
    description: "Two barracks with academy for medics. Early pressure into bio timing push.",
    tags: ["bio", "pressure", "timing"], games: 198, winrate: 52},
  %{name: "12 Hatch", race: "Z", matchup: "ZvP",
    description: "12 supply hatchery before spawning pool. Greedy economic opening.",
    tags: ["economic", "greedy", "macro"], games: 367, winrate: 49},
  %{name: "5 Rax Reaver Drop", race: "P", matchup: "PvT",
    description: "Aggressive shuttle reaver drop off one base. High risk, high reward timing attack.",
    tags: ["aggressive", "timing", "all-in"], games: 156, winrate: 54},
  %{name: "Mech (FD Style)", race: "T", matchup: "TvP",
    description: "Flash-style mech play. Siege tank contain with vulture flanks, transitioning to late game.",
    tags: ["mech", "contain", "late-game"], games: 289, winrate: 55},
  %{name: "5 Pool", race: "Z", matchup: "ZvZ",
    description: "Extremely early spawning pool for zergling rush. Cheese build, weak if scouted.",
    tags: ["cheese", "rush", "all-in"], games: 134, winrate: 48},
  %{name: "Fast DT", race: "P", matchup: "PvP",
    description: "Rush to dark templar archives. Wins if opponent has no detection.",
    tags: ["aggressive", "tech", "dark-templar"], games: 178, winrate: 51},
]

build_count =
  Enum.reduce(builds_data, 0, fn attrs, count ->
    existing = Repo.one(from(b in Build, where: b.name == ^attrs.name))

    if existing do
      count
    else
      Repo.insert!(Build.changeset(%Build{}, attrs))
      count + 1
    end
  end)

IO.puts("  #{build_count} builds seeded")

# ---

IO.puts("Seeding streams...")

streams_data = [
  %{channel_id: "flash", platform: "afreeca", player: "Flash"},
  %{channel_id: "rain_bw", platform: "afreeca", player: "Rain"},
  %{channel_id: "effort_bw", platform: "afreeca", player: "EffOrt"},
  %{channel_id: "mini_bw", platform: "afreeca", player: "Mini"},
  %{channel_id: "soulkey_bw", platform: "afreeca", player: "Soulkey"},
  %{channel_id: "last_bw", platform: "afreeca", player: "Last"},
  %{channel_id: "larva_bw", platform: "afreeca", player: "Larva"},
  %{channel_id: "bisu_bw", platform: "afreeca", player: "Bisu"},
]

stream_count =
  Enum.reduce(streams_data, 0, fn data, count ->
    player = players[data.player]

    existing =
      Repo.one(
        from(s in Stream,
          where: s.platform == ^data.platform and s.channel_id == ^data.channel_id
        )
      )

    if existing do
      count
    else
      attrs = %{
        channel_id: data.channel_id,
        platform: data.platform,
        player_id: player && player.id,
        is_live: false,
        viewer_count: 0
      }

      Repo.insert!(Stream.changeset(%Stream{}, attrs))
      count + 1
    end
  end)

IO.puts("  #{stream_count} streams seeded")

IO.puts("Done!")
