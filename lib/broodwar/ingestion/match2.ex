defmodule Broodwar.Ingestion.Match2 do
  @moduledoc """
  Parses Liquipedia "Match2" wikitext (StarCraft: Brood War wiki) into plain
  match maps. Pure: no I/O, no database.

  Handled syntax (verified against real pages, see `test/fixtures/liquipedia`):

    * containers: `{{Matchlist|id=...|M1header=...|M1={{Match ...}}}}`,
      `{{Bracket|Bracket/8|id=...|R1M1header=...|R1M1={{Match ...}}|RxMTP=...}}`,
      `{{SingleMatch|id=...|{{Match ...}}}}`
    * opponents: `{{1Opponent|Flash}}`, `{{1Opponent|Flash|race=t|score=2}}`,
      `{{1Opponent|p1=Flash|p1race=t}}`, `{{SoloOpponent|name=Flash|race=t}}`,
      optional `link=` / `p1link=` overriding the player page
    * maps: `{{Map|map=Radeon|winner=1}}`; `winner=skip` / `finished=skip`
      are unplayed; optional `race1=` / `race2=` per game (random players)
    * dates: `2024-02-26 19:20 {{Abbr/KST}}`, `January 16, 2008`,
      `September 2, 2018 - 19:00 {{Abbr/KST}}`, `2008-02-22`
    * `bestof` is inherited by later matches in the same container, as the
      Match2 templates do
    * walkovers: match-level `walkover=1|2`, or opponent `score=W|FF|DQ|L`

  Opponents without a race take it from elsewhere on the page (group
  tables, inline player templates) when that is unambiguous.

  `date_precision` says how a match's date was obtained: `"minute"` / `"day"`
  from the match itself, `"stage"` from the group table above it,
  `"inherited"` from the previous dated match on the page (pages are laid out
  chronologically), `"tournament"` from the infobox start date. Matches without a result (unplayed, TBD opponents) are
  returned in `:skipped`, never as matches.

  Series that only record a score (no per-map results, common on older
  brackets) get `inferred: true` games with no map, so they count for
  ratings but not for map statistics.
  """

  alias Broodwar.Ingestion.Wikitext

  @containers ~w(matchlist bracket singlematch)
  @match_key ~r/^(?:M\d+|R\d+M\d+|RxMTP|RxMBR|RxG\d+(?:M\d+)?)$/
  @max_maps 15

  @months ~w(january february march april may june july august september october november december)

  # Hours offset from UTC for timezone abbreviations Liquipedia uses.
  @tz_offsets %{
    "KST" => 9,
    "JST" => 9,
    "SGT" => 8,
    "AEST" => 10,
    "AEDT" => 11,
    "MSK" => 3,
    "EEST" => 3,
    "EET" => 2,
    "CEST" => 2,
    "CET" => 1,
    "BST" => 1,
    "UTC" => 0,
    "GMT" => 0,
    "EDT" => -4,
    "EST" => -5,
    "CDT" => -5,
    "PDT" => -7,
    "PST" => -8
  }

  @type game :: %{
          number: pos_integer(),
          map: String.t() | nil,
          winner: 1 | 2,
          race1: String.t() | nil,
          race2: String.t() | nil,
          inferred: boolean()
        }

  @type opponent :: %{
          name: String.t(),
          page: String.t(),
          race: String.t() | nil,
          score: String.t() | nil
        }

  @type match :: %{
          key: String.t(),
          order: non_neg_integer(),
          stage: String.t() | nil,
          round: String.t() | nil,
          played_at: DateTime.t() | nil,
          date_precision: String.t() | nil,
          best_of: pos_integer() | nil,
          opponent1: opponent(),
          opponent2: opponent(),
          score1: non_neg_integer(),
          score2: non_neg_integer(),
          winner: 1 | 2,
          walkover: boolean(),
          games: [game()]
        }

  @doc """
  Parses a page. Returns `%{matches, skipped, infobox, transclusions}`.

  `skipped` is a list of `%{key, reason}` for matches that were found but
  not turned into results; one bad match never aborts the page.
  """
  @spec parse_page(String.t()) :: %{
          matches: [match()],
          skipped: [%{key: String.t(), reason: atom() | String.t()}],
          infobox: map(),
          transclusions: [String.t()]
        }
  def parse_page(wikitext) do
    text = Wikitext.strip_comments(wikitext)
    top = Wikitext.templates(text)
    infobox = infobox(top)
    headings = headings(text)

    containers =
      top
      |> Enum.flat_map(&find_containers/1)
      |> Enum.with_index()

    {results, _acc} =
      Enum.flat_map_reduce(containers, {0, nil}, fn {container, idx}, {order, last_date} ->
        ctx = %{
          best_of: nil,
          date: last_date,
          stage_date: stage_date(top, headings, container.offset),
          start_date: infobox[:start_date]
        }

        stage = stage_at(headings, container.offset)
        {entries, last_date} = container_matches(container, idx, stage, ctx)

        {Enum.map(Enum.with_index(entries, order), &put_order/1),
         {order + length(entries), last_date}}
      end)

    races = page_races(text)

    %{
      matches: for({:ok, m} <- results, do: fill_races(m, races)),
      skipped: for({:skip, s} <- results, do: s),
      infobox: infobox,
      transclusions: transclusions(text)
    }
  end

  defp put_order({{:ok, m}, order}), do: {:ok, Map.put(m, :order, order)}
  defp put_order({skip, _order}), do: skip

  # -- Page structure --

  defp infobox(templates) do
    case Enum.find(templates, &(String.downcase(&1.name) == "infobox league")) do
      nil ->
        %{}

      t ->
        %{
          name: Wikitext.clean(Wikitext.get(t, "name")),
          abbreviation: Wikitext.get_any(t, ["abbreviation"]),
          start_date: parse_day(Wikitext.get(t, "sdate")),
          end_date: parse_day(Wikitext.get(t, "edate")),
          edition: Wikitext.get_any(t, ["edition"]),
          tier: Wikitext.get_any(t, ["liquipediatier"])
        }
    end
  end

  # Containers can sit inside other templates (tabs, boxes).
  defp find_containers(%{name: name} = t) do
    if container?(name) do
      [t]
    else
      t.params
      |> Enum.filter(fn {_key, value} -> String.contains?(value, "{{") end)
      |> Enum.flat_map(fn {_key, value} -> nested_containers(value, t.offset) end)
    end
  end

  defp nested_containers(value, offset) do
    value
    |> Wikitext.templates()
    |> Enum.flat_map(&find_containers/1)
    |> Enum.map(&%{&1 | offset: offset})
  end

  defp container?(name), do: String.downcase(name) in @containers

  defp headings(text) do
    ~r/^(={2,6})\s*(.+?)\s*\1\s*$/m
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [{start, _}, {_, level}, {ts, tl}] ->
      {start, level, Wikitext.clean(binary_part(text, ts, tl))}
    end)
  end

  # Stage = the level >= 3 headings above the container (e.g.
  # "Round of 24 / Group A"), else the nearest level 2 heading.
  defp stage_at(headings, offset) do
    stack =
      headings
      |> Enum.take_while(fn {start, _, _} -> start < offset end)
      |> Enum.reduce([], fn {_, level, title}, stack ->
        [{level, title} | Enum.reject(stack, fn {l, _} -> l >= level end)]
      end)
      |> Enum.reverse()

    case Enum.filter(stack, fn {level, _} -> level >= 3 end) do
      [] -> stack |> List.last({nil, nil}) |> elem(1)
      deep -> Enum.map_join(deep, " / ", &elem(&1, 1))
    end
  end

  # Group tables (e.g. {{GroupTableLeague|date=...}}) carry the day a group
  # was played; use it for matches in the container that follows, as long
  # as no heading sits between them.
  defp stage_date(top, headings, offset) do
    heading_start =
      headings
      |> Enum.take_while(fn {start, _, _} -> start < offset end)
      |> List.last({0, nil, nil})
      |> elem(0)

    top
    |> Enum.filter(fn t ->
      t.offset < offset and t.offset >= heading_start and not container?(t.name)
    end)
    |> Enum.reverse()
    |> Enum.find_value(fn t -> parse_datetime(Wikitext.get(t, "date")) end)
  end

  # Races mentioned anywhere on the page (group tables, inline players):
  # Match2 opponents often omit them because Liquipedia looks them up from
  # player data. A name seen with two different races is left out.
  defp page_races(text) do
    ~r/\{\{(?:solo|1)?Opponent\|[^{}]*\}\}|\{\{InlinePlayer\|[^{}]*\}\}/i
    |> Regex.scan(text)
    |> Enum.flat_map(fn [raw] ->
      t = Wikitext.parse_template(raw)
      name = Wikitext.get_any(t, ["1", "p1", "name"])
      page = Wikitext.get_any(t, ["link", "p1link"]) || name
      race = race(Wikitext.get_any(t, ["race", "p1race", "faction", "p1faction"]))
      if name && race, do: [{page, race}], else: []
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {page, races} ->
      case Enum.uniq(races) do
        [race] -> [{page, race}]
        _ -> []
      end
    end)
    |> Map.new()
  end

  defp fill_races(m, races) do
    %{m | opponent1: fill_race(m.opponent1, races), opponent2: fill_race(m.opponent2, races)}
  end

  defp fill_race(%{race: nil, page: page} = o, races), do: %{o | race: races[page]}
  defp fill_race(o, _races), do: o

  defp transclusions(text) do
    ~r/\{\{:([^|}]+)/
    |> Regex.scan(text)
    |> Enum.map(fn [_, page] -> String.trim(page) end)
    |> Enum.uniq()
  end

  # -- Containers --

  defp container_matches(container, idx, stage, ctx) do
    id = Wikitext.get_any(container, ["id"]) || "c#{idx}"
    title = Wikitext.clean(Wikitext.get_any(container, ["title"]))

    headers =
      for {key, value} <- container.params,
          String.ends_with?(key, "header"),
          into: %{},
          do: {String.replace_suffix(key, "header", ""), Wikitext.clean(value)}

    entries =
      container.params
      |> Enum.filter(fn {key, value} ->
        (Regex.match?(@match_key, key) or (key == "1" and single?(container))) and
          match_template?(value)
      end)

    {results, ctx} =
      Enum.map_reduce(entries, ctx, fn {key, value}, ctx ->
        match_key = "#{id}_#{key}"
        round = round_for(key, headers) || title
        parse_match(value, match_key, stage, round, ctx)
      end)

    {results, ctx.date}
  end

  defp single?(container), do: String.downcase(container.name) == "singlematch"

  defp match_template?(value) do
    case Wikitext.parse_template(value) do
      %{name: name} -> String.downcase(name) == "match"
      nil -> false
    end
  end

  # Matchlist: the most recent "M<j>header" with j <= i. Bracket: the most
  # recent "R<r>M<j>header" with j <= m in the same round.
  defp round_for(key, headers) do
    case Regex.run(~r/^(R\d+|Rx)?M?(\d+|TP|BR)$/, key) do
      [_, prefix, n] -> header_for(prefix, n, headers)
      _ -> nil
    end
  end

  defp header_for(prefix, n, headers) do
    case Integer.parse(n) do
      {i, ""} -> Enum.find_value(i..1//-1, fn j -> headers["#{prefix}M#{j}"] end)
      _ -> headers["#{prefix}M#{n}"] || if(n == "TP", do: "Third Place Match")
    end
  end

  # -- Matches --

  defp parse_match(value, key, stage, round, ctx) do
    t = Wikitext.parse_template(value)
    declared_bo = parse_int(Wikitext.get_any(t, ["bestof"])) || ctx.best_of
    {played_at, precision} = match_date(Wikitext.get_any(t, ["date"]), ctx)

    ctx = %{
      ctx
      | best_of: declared_bo,
        date: if(precision in ["minute", "day", "stage"], do: played_at, else: ctx.date)
    }

    best_of = declared_bo || listed_best_of(t)

    result =
      with {:ok, o1} <- opponent(Wikitext.get(t, "opponent1")),
           {:ok, o2} <- opponent(Wikitext.get(t, "opponent2")),
           {:ok, outcome} <- outcome(t, o1, o2) do
        {:ok,
         Map.merge(outcome, %{
           key: key,
           stage: stage,
           round: round,
           played_at: played_at,
           date_precision: precision,
           best_of: best_of,
           opponent1: o1,
           opponent2: o2
         })}
      else
        {:error, reason} -> {:skip, %{key: key, reason: reason}}
      end

    {result, ctx}
  rescue
    # A malformed match must never abort the rest of the page.
    e -> {{:skip, %{key: key, reason: Exception.message(e)}}, ctx}
  end

  defp opponent(nil), do: {:error, :missing_opponent}

  defp opponent(value) do
    case Wikitext.parse_template(value) do
      nil ->
        {:error, :unrecognized_opponent}

      t ->
        name = Wikitext.clean(Wikitext.get_any(t, ["1", "p1", "name"]))

        if name in [nil, ""] or String.downcase(name) in ["tbd", "bye", "tba"] do
          {:error, :tbd_opponent}
        else
          page = Wikitext.get_any(t, ["link", "p1link"]) || name

          {:ok,
           %{
             name: name,
             page: page,
             race: race(Wikitext.get_any(t, ["race", "p1race", "faction", "p1faction"])),
             score: Wikitext.get_any(t, ["score"]),
             win: Wikitext.get_any(t, ["win"])
           }}
        end
    end
  end

  defp outcome(t, o1, o2) do
    case walkover_winner(t, o1, o2) do
      w when w in [1, 2] -> {:ok, walkover_outcome(w)}
      nil -> played_outcome(t, o1, o2)
    end
  end

  defp walkover_outcome(winner) do
    {s1, s2} = if winner == 1, do: {1, 0}, else: {0, 1}
    %{winner: winner, walkover: true, score1: s1, score2: s2, games: []}
  end

  @forfeit ~w(ff dq l)
  defp walkover_winner(t, o1, o2) do
    s1 = String.downcase(o1.score || "")
    s2 = String.downcase(o2.score || "")

    cond do
      Wikitext.get(t, "walkover") in ["1", "2"] -> String.to_integer(Wikitext.get(t, "walkover"))
      s1 == "w" or s2 in @forfeit -> 1
      s2 == "w" or s1 in @forfeit -> 2
      true -> nil
    end
  end

  defp played_outcome(t, o1, o2) do
    games = games(t)
    {s1, s2} = series_score(games, o1, o2)
    winner = declared_winner(t, o1, o2) || score_winner(s1, s2)

    cond do
      winner == nil ->
        {:error, :no_result}

      games == [] and s1 + s2 > 0 ->
        {:ok,
         %{
           winner: winner,
           walkover: false,
           score1: s1,
           score2: s2,
           games: inferred_games(s1, s2, winner)
         }}

      games == [] ->
        {:error, :no_games}

      true ->
        {:ok, %{winner: winner, walkover: false, score1: s1, score2: s2, games: games}}
    end
  end

  # Without a declared bestof, an odd number of listed maps (played or
  # skipped) is the series length.
  defp listed_best_of(t) do
    n = Enum.count(1..@max_maps, &(Wikitext.get(t, "map#{&1}") != nil))
    if rem(n, 2) == 1, do: n
  end

  defp games(t) do
    1..@max_maps
    |> Enum.map(&Wikitext.parse_template(Wikitext.get(t, "map#{&1}")))
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn m ->
      Wikitext.get(m, "winner") in ["1", "2"] and Wikitext.get(m, "finished") != "skip"
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {m, n} ->
      %{
        number: n,
        map: Wikitext.clean(Wikitext.get_any(m, ["map"])),
        winner: String.to_integer(Wikitext.get(m, "winner")),
        race1: race(Wikitext.get_any(m, ["race1", "p1race"])),
        race2: race(Wikitext.get_any(m, ["race2", "p2race"])),
        inferred: false
      }
    end)
  end

  # Per-map results win; numeric opponent scores are the fallback for
  # brackets that only record the series score.
  defp series_score([], o1, o2), do: {parse_int(o1.score) || 0, parse_int(o2.score) || 0}

  defp series_score(games, _o1, _o2) do
    {Enum.count(games, &(&1.winner == 1)), Enum.count(games, &(&1.winner == 2))}
  end

  defp declared_winner(t, o1, o2) do
    cond do
      Wikitext.get(t, "winner") in ["1", "2"] -> String.to_integer(Wikitext.get(t, "winner"))
      o1.win == "1" -> 1
      o2.win == "1" -> 2
      true -> nil
    end
  end

  defp score_winner(s1, s2) when s1 > s2, do: 1
  defp score_winner(s1, s2) when s2 > s1, do: 2
  defp score_winner(_, _), do: nil

  # Game order inside a score-only series is unknown; use a fixed order
  # (series loser's wins first) so rating recomputes stay deterministic.
  defp inferred_games(s1, s2, winner) do
    {loser_wins, winner_wins} = if winner == 1, do: {s2, s1}, else: {s1, s2}
    loser = 3 - winner

    (List.duplicate(loser, loser_wins) ++ List.duplicate(winner, winner_wins))
    |> Enum.with_index(1)
    |> Enum.map(fn {w, n} ->
      %{number: n, map: nil, winner: w, race1: nil, race2: nil, inferred: true}
    end)
  end

  # -- Dates --

  defp match_date(raw, ctx) do
    case parse_datetime(raw) do
      {dt, precision} ->
        {dt, precision}

      nil when ctx.stage_date != nil ->
        {elem(ctx.stage_date, 0), "stage"}

      nil when ctx.date != nil ->
        {ctx.date, "inherited"}

      nil when ctx.start_date != nil ->
        {DateTime.new!(ctx.start_date, ~T[00:00:00]), "tournament"}

      nil ->
        {nil, nil}
    end
  end

  @doc """
  Parses a Liquipedia date string. Returns `{utc_datetime, precision}` with
  precision `"minute"` or `"day"`, or `nil`.
  """
  @spec parse_datetime(String.t() | nil) :: {DateTime.t(), String.t()} | nil
  def parse_datetime(nil), do: nil

  def parse_datetime(raw) do
    tz =
      case Regex.run(~r/\{\{Abbr\/([A-Za-z]+)\}\}/i, raw) do
        [_, abbr] -> String.upcase(abbr)
        _ -> nil
      end

    with {date, time} <- date_and_time(raw) do
      to_utc(date, time, tz)
    end
  end

  defp date_and_time(raw) do
    iso = Regex.run(~r/(\d{4})-(\d{1,2})-(\d{1,2})(?:\D{0,4}?(\d{1,2}):(\d{2}))?/, raw)

    long =
      Regex.run(~r/([A-Za-z]+)\.?\s+(\d{1,2}),?\s+(\d{4})(?:\D{0,4}?(\d{1,2}):(\d{2}))?/, raw)

    cond do
      iso ->
        build_date(Enum.at(iso, 1), Enum.at(iso, 2), Enum.at(iso, 3), Enum.drop(iso, 4))

      long && month(Enum.at(long, 1)) ->
        build_date(
          Enum.at(long, 3),
          month(Enum.at(long, 1)),
          Enum.at(long, 2),
          Enum.drop(long, 4)
        )

      true ->
        nil
    end
  end

  defp build_date(y, m, d, time_parts) do
    case Date.new(to_int(y), to_int(m), to_int(d)) do
      {:ok, date} -> {date, build_time(time_parts)}
      _ -> nil
    end
  end

  defp build_time([h, min]), do: Time.new(to_int(h), to_int(min), 0) |> elem_ok()
  defp build_time(_), do: nil

  defp elem_ok({:ok, v}), do: v
  defp elem_ok(_), do: nil

  defp to_utc(date, nil, _tz), do: {DateTime.new!(date, ~T[00:00:00]), "day"}

  defp to_utc(date, time, tz) do
    offset = Map.get(@tz_offsets, tz, 0)
    dt = date |> DateTime.new!(time) |> DateTime.add(-offset * 3600, :second)
    {dt, "minute"}
  end

  defp month(name) do
    name = String.downcase(name)

    case Enum.find_index(@months, &(&1 == name or String.slice(&1, 0, 3) == name)) do
      nil -> nil
      i -> i + 1
    end
  end

  defp parse_day(nil), do: nil

  defp parse_day(raw) do
    case date_and_time(raw) do
      {date, _} -> date
      nil -> nil
    end
  end

  # -- Helpers --

  @doc "Normalizes a race token (`t`, `Terran`, ...) to `T`/`P`/`Z`/`R`."
  @spec race(String.t() | nil) :: String.t() | nil
  def race(nil), do: nil

  def race(value) do
    case value |> String.trim() |> String.downcase() do
      r when r in ["t", "terran"] -> "T"
      r when r in ["p", "protoss"] -> "P"
      r when r in ["z", "zerg"] -> "Z"
      r when r in ["r", "random"] -> "R"
      _ -> nil
    end
  end

  defp parse_int(nil), do: nil

  defp parse_int(value) do
    case Integer.parse(String.trim(value)) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp to_int(n) when is_integer(n), do: n
  defp to_int(s), do: String.to_integer(s)
end
