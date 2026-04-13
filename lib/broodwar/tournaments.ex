defmodule Broodwar.Tournaments do
  @moduledoc """
  Context for tournament data sourced from Liquipedia.
  """
  import Ecto.Query
  alias Broodwar.Repo
  alias Broodwar.Tournaments.Tournament

  def list_by_series(short_name) do
    Repo.all(
      from t in Tournament,
        where: t.short_name == ^short_name,
        order_by: [desc: t.season]
    )
  end

  def get_season(short_name, season) do
    Repo.one(
      from t in Tournament,
        where: t.short_name == ^short_name and t.season == ^season
    )
  end

  def list_series do
    Repo.all(
      from t in Tournament,
        where: not is_nil(t.short_name),
        group_by: t.short_name,
        select: %{
          short_name: t.short_name,
          count: count(t.id),
          min_year: min(t.year),
          max_year: max(t.year)
        },
        order_by: [desc: count(t.id)]
    )
  end

  def champion_counts do
    Repo.all(from t in Tournament, where: not is_nil(t.short_name))
    |> Enum.flat_map(fn t ->
      case t.liquipedia_data["first_place"] do
        nil -> []
        "" -> []
        name -> [name]
      end
    end)
    |> Enum.frequencies()
    |> Enum.map(fn {name, count} -> %{name: name, count: count} end)
    |> Enum.sort_by(fn c -> -c.count end)
  end
end
