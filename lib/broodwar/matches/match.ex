defmodule Broodwar.Matches.Match do
  @moduledoc """
  A series between two players (e.g. a Bo5). Per-map results live in
  `Broodwar.Matches.Game`. Liquipedia-sourced series are keyed by
  `(source_page, source_match_id)` and record the page revision they were
  read from.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "matches" do
    belongs_to :tournament, Broodwar.Tournaments.Tournament
    belongs_to :map, Broodwar.Maps.Map
    belongs_to :player_a, Broodwar.Players.Player
    belongs_to :player_b, Broodwar.Players.Player
    belongs_to :winner, Broodwar.Players.Player
    has_many :games, Broodwar.Matches.Game, preload_order: [asc: :game_number]

    field :stage, :string
    field :round, :string
    field :race_a, :string
    field :race_b, :string
    field :score_a, :integer, default: 0
    field :score_b, :integer, default: 0
    field :best_of, :integer
    field :walkover, :boolean, default: false
    field :played_at, :utc_datetime
    field :date_precision, :string
    field :source, :string
    field :source_page, :string
    field :source_match_id, :string
    field :source_revision_id, :integer
    field :page_order, :integer

    timestamps()
  end

  @required_fields [:player_a_id, :player_b_id]
  @optional_fields [
    :tournament_id,
    :map_id,
    :winner_id,
    :stage,
    :round,
    :race_a,
    :race_b,
    :score_a,
    :score_b,
    :best_of,
    :walkover,
    :played_at,
    :date_precision,
    :source,
    :source_page,
    :source_match_id,
    :source_revision_id,
    :page_order
  ]
  @valid_races ~w(T P Z R)

  @doc false
  def changeset(match, attrs) do
    match
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:race_a, @valid_races)
    |> validate_inclusion(:race_b, @valid_races)
    |> foreign_key_constraint(:player_a_id)
    |> foreign_key_constraint(:player_b_id)
    |> foreign_key_constraint(:tournament_id)
    |> foreign_key_constraint(:map_id)
    |> unique_constraint([:source_page, :source_match_id])
  end
end
