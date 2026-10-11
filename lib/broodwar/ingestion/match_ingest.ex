defmodule Broodwar.Ingestion.MatchIngest do
  @moduledoc """
  Ingests series and games from one Liquipedia tournament page.

  Idempotent: series are upserted on `(source_page, source_match_id)` and
  their games are replaced, so re-running a page reflects the current
  revision. Series that disappeared from the page are deleted. Each series
  is written in its own transaction; a failure (e.g. an ambiguous player)
  is reported and the rest of the page still goes in.

  Ratings are not touched here: callers run `Broodwar.Ratings.recompute/0`
  after a batch of pages.
  """
  import Ecto.Query
  require Logger

  alias Broodwar.Ingestion.Liquipedia
  alias Broodwar.Ingestion.Match2
  alias Broodwar.Ingestion.Wikitext
  alias Broodwar.Maps.Map, as: GameMap
  alias Broodwar.Matches.Game
  alias Broodwar.Matches.Match
  alias Broodwar.Players.Identity
  alias Broodwar.Players.Player
  alias Broodwar.Repo
  alias Broodwar.Tournaments.Tournament

  @type summary :: %{
          page: String.t(),
          revision_id: integer(),
          matches_found: non_neg_integer(),
          upserted: non_neg_integer(),
          games: non_neg_integer(),
          walkovers: non_neg_integer(),
          deleted: non_neg_integer(),
          skipped: [map()],
          failed: [map()],
          transclusions: [String.t()]
        }

  @doc "Fetches `title` from Liquipedia and ingests it."
  @spec ingest_page(String.t()) :: {:ok, summary()} | {:error, term()}
  def ingest_page(title) do
    with {:ok, page} <- Liquipedia.get_page_revision(title) do
      ingest_wikitext(page.title, page.revision_id, page.content)
    end
  end

  @doc "Ingests already-fetched wikitext (used by tests and `ingest_page/1`)."
  @spec ingest_wikitext(String.t(), integer(), String.t()) :: {:ok, summary()}
  def ingest_wikitext(title, revision_id, wikitext) do
    parsed = Match2.parse_page(wikitext)
    tournament = ensure_tournament(title, parsed.infobox)
    source = %{page: title, revision_id: revision_id, tournament_id: tournament && tournament.id}

    results = Enum.map(parsed.matches, &{&1, upsert(&1, source)})

    ok = for {m, {:ok, games}} <- results, do: {m, games}
    failed = for {m, {:error, reason}} <- results, do: %{key: m.key, reason: describe(reason)}

    # Keys that are still on the page (including failed and skipped ones)
    # stay; anything else from this page is gone upstream.
    keep = Enum.map(parsed.matches, & &1.key) ++ Enum.map(parsed.skipped, & &1.key)

    {deleted, _} =
      Repo.delete_all(
        from m in Match, where: m.source_page == ^title and m.source_match_id not in ^keep
      )

    Broodwar.Cache.invalidate_all()

    {:ok,
     %{
       page: title,
       revision_id: revision_id,
       matches_found: length(parsed.matches) + length(parsed.skipped),
       upserted: length(ok),
       games: ok |> Enum.map(&elem(&1, 1)) |> Enum.sum(),
       walkovers: Enum.count(ok, fn {m, _} -> m.walkover end),
       deleted: deleted,
       skipped: Enum.map(parsed.skipped, &%{key: &1.key, reason: describe(&1.reason)}),
       failed: failed,
       transclusions: parsed.transclusions
     }}
  end

  @doc """
  Fills in races for Liquipedia players that have none, from the
  `race=` field of their player pages, fetched 50 pages per request. Then
  backfills null races on their series and games.

  Needed because modern Match2 pages omit races (Liquipedia resolves them
  from player data). Returns `{:ok, updated_player_count}`.
  """
  @spec fill_missing_races(keyword()) :: {:ok, non_neg_integer()} | {:error, term()}
  def fill_missing_races(opts \\ []) do
    fetch = Keyword.get(opts, :fetch, &Liquipedia.get_pages/1)

    players =
      Repo.all(
        from p in Player,
          where: is_nil(p.race) and not is_nil(p.liquipedia_page),
          where:
            p.id in subquery(from m in Match, select: m.player_a_id) or
              p.id in subquery(from m in Match, select: m.player_b_id),
          order_by: p.id
      )

    players
    |> Enum.chunk_every(50)
    |> Enum.reduce_while({:ok, 0}, fn chunk, {:ok, n} ->
      case fetch.(Enum.map(chunk, & &1.liquipedia_page)) do
        {:ok, pages} -> {:cont, {:ok, n + apply_races(chunk, pages)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp apply_races(players, pages) do
    players
    |> Enum.map(fn p ->
      {p, pages[p.liquipedia_page] && infobox_race(pages[p.liquipedia_page])}
    end)
    |> Enum.filter(fn {_p, race} -> race in ~w(T P Z R) end)
    |> Enum.each(fn {p, race} ->
      Repo.transaction(fn ->
        Repo.update_all(where(Player, id: ^p.id), set: [race: race])
        backfill(Match, p.id, race)
        backfill(Game, p.id, race)
      end)
    end)
    |> then(fn _ -> Enum.count(players, &(pages[&1.liquipedia_page] != nil)) end)
  end

  defp backfill(schema, player_id, race) do
    Repo.update_all(from(r in schema, where: r.player_a_id == ^player_id and is_nil(r.race_a)),
      set: [race_a: race]
    )

    Repo.update_all(from(r in schema, where: r.player_b_id == ^player_id and is_nil(r.race_b)),
      set: [race_b: race]
    )
  end

  defp infobox_race(wikitext) do
    wikitext
    |> Wikitext.strip_comments()
    |> Wikitext.templates()
    |> Enum.find(&(String.downcase(&1.name) == "infobox player"))
    |> case do
      nil -> nil
      t -> Match2.race(Wikitext.get_any(t, ["race"]) || "")
    end
  end

  # -- Series --

  defp upsert(m, source) do
    Repo.transaction(fn ->
      with {:ok, pa} <- resolve(m.opponent1),
           {:ok, pb} <- resolve(m.opponent2),
           :ok <- distinct_players(pa, pb),
           {:ok, match} <- write_match(m, source, pa, pb) do
        write_games(match, m, source, pa, pb)
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  rescue
    e ->
      Logger.warning("[MatchIngest] #{m.key}: #{Exception.message(e)}")
      {:error, Exception.message(e)}
  end

  defp resolve(opponent) do
    case Identity.resolve_liquipedia(opponent, race: opponent.race) do
      {:ok, player} -> {:ok, player}
      {:error, reason} -> {:error, {:player, opponent.page, reason}}
    end
  end

  defp distinct_players(%{id: id}, %{id: id}), do: {:error, :same_player}
  defp distinct_players(_pa, _pb), do: :ok

  defp write_match(m, source, pa, pb) do
    attrs = %{
      tournament_id: source.tournament_id,
      stage: m.stage,
      round: m.round,
      player_a_id: pa.id,
      player_b_id: pb.id,
      winner_id: if(m.winner == 1, do: pa.id, else: pb.id),
      race_a: m.opponent1.race || pa.race,
      race_b: m.opponent2.race || pb.race,
      score_a: m.score1,
      score_b: m.score2,
      best_of: m.best_of,
      walkover: m.walkover,
      played_at: m.played_at,
      date_precision: m.date_precision,
      source: "liquipedia",
      source_page: source.page,
      source_match_id: m.key,
      source_revision_id: source.revision_id,
      page_order: m.order
    }

    (Repo.get_by(Match, source_page: source.page, source_match_id: m.key) || %Match{})
    |> Match.changeset(attrs)
    |> Repo.insert_or_update()
  end

  defp write_games(match, m, source, pa, pb) do
    Repo.delete_all(from g in Game, where: g.match_id == ^match.id)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    rows =
      Enum.map(m.games, fn g ->
        map = g.map && ensure_map(g.map)

        %{
          match_id: match.id,
          game_number: g.number,
          map_id: map && map.id,
          map_name: g.map,
          player_a_id: pa.id,
          player_b_id: pb.id,
          winner_id: if(g.winner == 1, do: pa.id, else: pb.id),
          race_a: g.race1 || match.race_a,
          race_b: g.race2 || match.race_b,
          played_at: match.played_at,
          inferred: g.inferred,
          source: "liquipedia",
          source_page: source.page,
          page_order: m.order,
          inserted_at: now,
          updated_at: now
        }
      end)

    {count, _} = Repo.insert_all(Game, rows)
    count
  end

  defp ensure_map(name) do
    Repo.one(
      from m in GameMap, where: fragment("lower(?)", m.name) == ^String.downcase(name), limit: 1
    ) ||
      Repo.insert!(GameMap.changeset(%GameMap{}, %{name: name}),
        on_conflict: :nothing,
        conflict_target: :name
      )
      |> case do
        %GameMap{id: nil} -> Repo.get_by!(GameMap, name: name)
        map -> map
      end
  end

  # -- Tournament --

  defp ensure_tournament(title, infobox) do
    variants = [title, String.replace(title, " ", "_")]

    Repo.one(from t in Tournament, where: t.liquipedia_page in ^variants, limit: 1) ||
      create_tournament(title, infobox)
  end

  defp create_tournament(title, infobox) do
    season = parse_int(infobox[:edition])
    short_name = infobox[:abbreviation]

    attrs = %{
      name: infobox[:name] || title,
      short_name: short_name,
      season: season,
      year: infobox[:start_date] && infobox[:start_date].year,
      liquipedia_page: title
    }

    case Repo.insert(Tournament.changeset(%Tournament{}, attrs)) do
      {:ok, t} ->
        t

      # (short_name, season) already exists, e.g. created by TournamentSync
      # under a different page spelling.
      {:error, _} ->
        Repo.one(
          from t in Tournament,
            where: t.short_name == ^short_name and t.season == ^season,
            limit: 1
        )
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp describe({:player, page, {:ambiguous, players}}),
    do:
      "ambiguous player #{page}: candidates #{Enum.map_join(players, ", ", &"#{&1.name} (##{&1.id})")}"

  defp describe({:player, page, reason}), do: "player #{page}: #{inspect(reason)}"
  defp describe(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)
end
