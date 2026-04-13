defmodule Broodwar.Players.Player do
  use Ecto.Schema
  import Ecto.Changeset

  schema "players" do
    field :name, :string
    field :real_name, :string
    field :real_name_ko, :string
    field :aliases, {:array, :string}, default: []
    field :race, :string
    field :country, :string
    field :rating, :integer
    field :birth_date, :string
    field :team, :string
    field :status, :string, default: "active"
    field :image_url, :string
    field :liquipedia_page, :string
    field :liquipedia_data, :map, default: %{}

    timestamps()
  end

  @required_fields [:name]
  @optional_fields [
    :real_name, :real_name_ko, :aliases, :race, :country, :rating,
    :birth_date, :team, :status, :image_url, :liquipedia_page, :liquipedia_data
  ]
  @valid_races ~w(T P Z R)

  @doc false
  def changeset(player, attrs) do
    player
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:race, @valid_races)
    |> unique_constraint(:name)
  end

  def age(%__MODULE__{birth_date: nil}), do: nil

  def age(%__MODULE__{birth_date: bd}) do
    case Date.from_iso8601(bd) do
      {:ok, birth} ->
        today = Date.utc_today()
        years = today.year - birth.year
        if Date.compare(Date.new!(today.year, birth.month, birth.day), today) == :gt, do: years - 1, else: years

      _ ->
        nil
    end
  end

  def race_name("T"), do: "Terran"
  def race_name("P"), do: "Protoss"
  def race_name("Z"), do: "Zerg"
  def race_name(_), do: "Unknown"
end
