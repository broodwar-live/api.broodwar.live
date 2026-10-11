defmodule Broodwar.Players.IdentityTest do
  use Broodwar.DataCase

  alias Broodwar.Players.Identity
  alias Broodwar.Players.Player

  test "normalize_alias/1 ignores case, underscores and whitespace" do
    assert Identity.normalize_alias("Sn Ow") == "snow"
    assert Identity.normalize_alias("Flash_(Korean player)") == "flash(koreanplayer)"
  end

  test "resolve_liquipedia/2 creates a player once and then reuses it" do
    assert {:ok, %Player{id: id, liquipedia_page: "Flash"}} =
             Identity.resolve_liquipedia(%{page: "Flash", name: "Flash"}, race: "T")

    assert {:ok, %Player{id: ^id, race: "T"}} =
             Identity.resolve_liquipedia(%{page: "flash", name: "FlaSh"})

    assert Repo.aggregate(Player, :count) == 1
  end

  test "resolve_liquipedia/2 adopts an unlinked player with a matching alias" do
    {:ok, p} = Repo.insert(Player.changeset(%Player{}, %{name: "이영호"}))
    Identity.add_alias(p, "Flash", "profile")

    assert {:ok, %Player{id: id, liquipedia_page: "Flash"}} =
             Identity.resolve_liquipedia(%{page: "Flash", name: "Flash"})

    assert id == p.id
  end

  test "resolve_liquipedia/2 does not merge players linked to different pages" do
    {:ok, korean} = Identity.resolve_liquipedia(%{page: "Sea", name: "Sea"})

    assert {:ok, other} = Identity.resolve_liquipedia(%{page: "Sea (Polish player)", name: "Sea"})
    assert other.id != korean.id
    assert other.name == "Sea (Polish player)"
  end

  test "resolve_in_game/1 never creates players" do
    assert {:error, {:unknown, []}} = Identity.resolve_in_game(["NoSuchPlayer"])
    assert Repo.aggregate(Player, :count) == 0
  end

  test "resolve_in_game/1 with a shared alias is ambiguous" do
    {:ok, a} = Identity.resolve_liquipedia(%{page: "A", name: "A"})
    {:ok, b} = Identity.resolve_liquipedia(%{page: "B", name: "B"})
    Identity.add_alias(a, "Shared", "admin")
    Identity.add_alias(b, "shared", "admin")

    assert {:error, {:ambiguous, players}} = Identity.resolve_in_game(["SHARED"])
    assert Enum.map(players, & &1.id) |> Enum.sort() == Enum.sort([a.id, b.id])
  end
end
