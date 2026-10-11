defmodule Broodwar.Players.Identity do
  @moduledoc """
  Resolves external names to `Player` rows.

  Players are only ever *created* from Liquipedia identities (a player page
  linked from match wikitext). In-game names from replays are resolved
  against known aliases and never create players: an unknown or ambiguous
  name is an error the admin has to settle explicitly.

  Matching is on `normalize_alias/1` (case-insensitive, underscores and
  whitespace ignored), so `"SnOw"`, `"snow"` and `"Sn Ow"` are the same key.
  """
  import Ecto.Query

  alias Broodwar.Players.Player
  alias Broodwar.Players.PlayerAlias
  alias Broodwar.Repo

  @type resolve_error ::
          {:ambiguous, [Player.t()]} | {:unknown, [Player.t()]} | {:invalid, term()}

  @doc "Normalized lookup key for a name or page title."
  @spec normalize_alias(String.t()) :: String.t()
  def normalize_alias(value) do
    value
    |> String.replace("_", " ")
    |> String.downcase()
    |> String.replace(~r/\s+/u, "")
  end

  @doc """
  Resolves a Liquipedia opponent (`page` = linked page title, `name` =
  display name) to a player, in this order:

    1. a player already linked to that Liquipedia page;
    2. an unlinked player (no Liquipedia page yet) with a matching alias,
       which is then linked to the page;
    3. otherwise a new player is created from the Liquipedia identity.

  Several candidates at step 1 or 2 is `{:error, {:ambiguous, players}}`.
  """
  @spec resolve_liquipedia(
          %{required(:page) => String.t(), required(:name) => String.t()},
          keyword()
        ) ::
          {:ok, Player.t()} | {:error, resolve_error()}
  def resolve_liquipedia(%{page: page, name: name}, opts \\ []) do
    race = opts[:race]

    case players_by_alias([page], source: "liquipedia") do
      [player] ->
        {:ok, maybe_set_race(player, race)}

      [_ | _] = many ->
        {:error, {:ambiguous, many}}

      [] ->
        case unlinked_players_by_alias([page, name]) do
          [player] -> adopt(player, page, name, race)
          [_ | _] = many -> {:error, {:ambiguous, many}}
          [] -> create_from_liquipedia(page, name, race)
        end
    end
  end

  @doc """
  Resolves in-game names (e.g. the raw replay name and a clan-tag-stripped
  variant) to exactly one existing player. Never creates players.

  Returns `{:error, {:unknown, suggestions}}` when nothing matches and
  `{:error, {:ambiguous, candidates}}` when several players do.
  """
  @spec resolve_in_game([String.t() | nil]) :: {:ok, Player.t()} | {:error, resolve_error()}
  def resolve_in_game(names) do
    names = names |> Enum.reject(&(&1 in [nil, ""])) |> Enum.uniq()

    case players_by_alias(names) do
      [player] -> {:ok, player}
      [_ | _] = many -> {:error, {:ambiguous, many}}
      [] -> {:error, {:unknown, suggestions(names)}}
    end
  end

  @doc "Records an alias for a player (no-op if it already exists)."
  @spec add_alias(Player.t(), String.t() | nil, String.t()) :: :ok
  def add_alias(_player, value, _source) when value in [nil, ""], do: :ok

  def add_alias(%Player{id: id}, value, source) do
    normalized = normalize_alias(value)

    if normalized != "" do
      %PlayerAlias{}
      |> PlayerAlias.changeset(%{
        player_id: id,
        alias: value,
        normalized: normalized,
        source: source
      })
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:player_id, :normalized])
    end

    :ok
  end

  # -- Private --

  defp players_by_alias(values, opts \\ []) do
    keys = values |> Enum.reject(&(&1 in [nil, ""])) |> Enum.map(&normalize_alias/1)

    PlayerAlias
    |> where([a], a.normalized in ^keys)
    |> then(fn q -> if opts[:source], do: where(q, [a], a.source == ^opts[:source]), else: q end)
    |> join(:inner, [a], p in Player, on: p.id == a.player_id)
    |> distinct(true)
    |> order_by([_a, p], p.id)
    |> select([_a, p], p)
    |> Repo.all()
  end

  # Players with a matching alias that are not yet tied to any Liquipedia
  # page. A player linked to a *different* page is a different person.
  defp unlinked_players_by_alias(values) do
    candidates = players_by_alias(values)
    ids = Enum.map(candidates, & &1.id)

    linked =
      Repo.all(
        from a in PlayerAlias,
          where: a.source == "liquipedia" and a.player_id in ^ids,
          select: a.player_id
      )

    Enum.reject(candidates, &(&1.id in linked or &1.liquipedia_page != nil))
  end

  defp adopt(player, page, name, race) do
    attrs = if player.liquipedia_page, do: %{}, else: %{liquipedia_page: page}

    with {:ok, player} <- update_player(player, maybe_race_attrs(attrs, player, race)) do
      add_alias(player, page, "liquipedia")
      add_alias(player, name, "name")
      {:ok, player}
    end
  end

  defp create_from_liquipedia(page, name, race) do
    display = Enum.find([name, page], &(not name_taken?(&1)))

    if display do
      %Player{}
      |> Player.changeset(%{name: display, liquipedia_page: page, race: race})
      |> Repo.insert()
      |> case do
        {:ok, player} ->
          add_alias(player, page, "liquipedia")
          add_alias(player, name, "name")
          {:ok, player}

        {:error, changeset} ->
          {:error, {:invalid, changeset}}
      end
    else
      {:error, {:ambiguous, Repo.all(from p in Player, where: p.name in ^[name, page])}}
    end
  end

  defp name_taken?(name), do: Repo.exists?(from p in Player, where: p.name == ^name)

  defp maybe_set_race(%Player{race: nil} = player, race) when is_binary(race) do
    case update_player(player, %{race: race}) do
      {:ok, player} -> player
      _ -> player
    end
  end

  defp maybe_set_race(player, _race), do: player

  defp maybe_race_attrs(attrs, %Player{race: nil}, race) when is_binary(race),
    do: Map.put(attrs, :race, race)

  defp maybe_race_attrs(attrs, _player, _race), do: attrs

  defp update_player(player, attrs) when attrs == %{}, do: {:ok, player}

  defp update_player(player, attrs) do
    case Repo.update(Player.changeset(player, attrs)) do
      {:ok, player} -> {:ok, player}
      {:error, changeset} -> {:error, {:invalid, changeset}}
    end
  end

  defp suggestions([]), do: []

  defp suggestions(names) do
    prefixes =
      names
      |> Enum.map(&normalize_alias/1)
      |> Enum.filter(&(String.length(&1) >= 3))
      |> Enum.map(&(String.slice(&1, 0, 3) <> "%"))

    case prefixes do
      [] ->
        []

      [first | rest] ->
        condition =
          Enum.reduce(rest, dynamic([a], like(a.normalized, ^first)), fn prefix, acc ->
            dynamic([a], ^acc or like(a.normalized, ^prefix))
          end)

        PlayerAlias
        |> where(^condition)
        |> join(:inner, [a], p in Player, on: p.id == a.player_id)
        |> distinct(true)
        |> order_by([_a, p], p.name)
        |> limit(10)
        |> select([_a, p], p)
        |> Repo.all()
    end
  end
end
