defmodule Broodwar.Ingestion.Match2Test do
  use ExUnit.Case, async: true

  alias Broodwar.Ingestion.Match2

  # Fixtures are raw wikitext from Liquipedia (CC-BY-SA 3.0), fetched via
  # action=query&prop=revisions on 2026-10-11:
  #   asl_s17_rev542482.wiki          https://liquipedia.net/starcraft/index.php?oldid=542482
  #     "AfreecaTV/StarCraft League Remastered/17" — modern Match2, KST times
  #   asl_s6_rev538330.wiki           https://liquipedia.net/starcraft/index.php?oldid=538330
  #     "AfreecaTV/StarCraft League Remastered/6" — SoloOpponent, walkovers,
  #     group-table dates, score-only bracket
  #   bacchus_osl_2008_rev541187.wiki https://liquipedia.net/starcraft/index.php?oldid=541187
  #     "2008 Bacchus OSL" — Starleague era, long-form dates, opponent scores
  @dir Path.expand("../../fixtures/liquipedia", __DIR__)

  defp fixture(name), do: Match2.parse_page(File.read!(Path.join(@dir, name)))
  defp find(result, key), do: Enum.find(result.matches, &(&1.key == key))

  describe "ASL Season 17 fixture" do
    setup do
      %{page: fixture("asl_s17_rev542482.wiki")}
    end

    test "parse_page/1 finds every series with per-map games", %{page: page} do
      assert length(page.matches) == 57
      assert page.skipped == []
      assert Enum.sum(Enum.map(page.matches, &length(&1.games))) == 100
      assert page.infobox.name == "ASL Season 17"
      assert page.infobox.start_date == ~D[2024-02-26]
    end

    test "parse_page/1 converts KST times to UTC and keeps context", %{page: page} do
      m = find(page, "ASL17R24GA_M1")
      assert m.played_at == ~U[2024-02-26 10:20:00Z]
      assert m.date_precision == "minute"
      assert m.stage == "Round of 24 / Group A"
      assert m.round == "Opening Matches"
      assert {m.opponent1.name, m.opponent2.name} == {"Light", "ZeLoT"}
      assert [%{map: "Radeon", winner: 1, inferred: false}] = m.games
    end

    test "parse_page/1 inherits bestof within a container", %{page: page} do
      # R1M1 declares bestof=5; R1M2..R1M4 inherit it.
      assert find(page, "ASL17R08PO_R1M1").best_of == 5
      assert find(page, "ASL17R08PO_R1M2").best_of == 5
      assert find(page, "ASL17R08PO_R2M2").best_of == 7
      # Ro16 group: M3 sets bestof=3 after Bo1 openers.
      assert find(page, "ASL17R16GA_M2").best_of == 1
      assert find(page, "ASL17R16GA_M3").best_of == 3
    end

    test "parse_page/1 skips finished=skip maps", %{page: page} do
      final = find(page, "ASL17R16GA_M3")
      assert length(final.games) == 2
      assert {final.score1, final.score2, final.winner} == {2, 0, 1}
    end

    test "parse_page/1 orders matches as they appear on the page", %{page: page} do
      orders = Enum.map(page.matches, & &1.order)
      assert orders == Enum.to_list(0..56)
      assert List.last(page.matches).key == "ASL17R08PO_R3M1"
    end
  end

  describe "ASL Season 6 fixture" do
    setup do
      %{page: fixture("asl_s6_rev538330.wiki")}
    end

    test "parse_page/1 marks match-level walkovers without games", %{page: page} do
      wo = find(page, "fndC08cTEd_M1")
      assert wo.walkover
      assert wo.winner == 1
      assert wo.games == []
      assert find(page, "fndC08cTEd_M4").winner == 2
      assert Enum.count(page.matches, & &1.walkover) == 2
    end

    test "parse_page/1 reads SoloOpponent names and races", %{page: page} do
      m = find(page, "Liee4NMRxO_M1")
      assert %{name: "Sea", race: "T"} = m.opponent1
      assert %{name: "Horang2", race: "P"} = m.opponent2
    end

    test "parse_page/1 dates undated matches from the group table", %{page: page} do
      m = find(page, "Liee4NMRxO_M1")
      assert m.date_precision == "stage"
      assert m.played_at == ~U[2018-09-02 10:00:00Z]
    end

    test "parse_page/1 infers games for score-only bracket series", %{page: page} do
      final = find(page, "aTlzn2LRfZ_R3M1")
      assert {final.score1, final.score2, final.winner} == {3, 2, 1}
      assert length(final.games) == 5
      assert Enum.all?(final.games, &(&1.inferred and is_nil(&1.map)))
      # Missing date: inherited from the last dated match on the page.
      assert final.date_precision == "inherited"
      assert find(page, "aTlzn2LRfZ_RxMTP").round == "3rd Place Match (Bo5)"
    end
  end

  describe "2008 Bacchus OSL fixture" do
    setup do
      %{page: fixture("bacchus_osl_2008_rev541187.wiki")}
    end

    test "parse_page/1 reads long-form dates", %{page: page} do
      m = find(page, "vjwIfFur3u_M1")
      assert m.played_at == ~U[2008-01-16 00:00:00Z]
      assert m.date_precision == "day"
      assert m.best_of == 1
    end

    test "parse_page/1 inherits a missing date from the previous match", %{page: page} do
      m = find(page, "tUfApkmcCn_M2")
      assert m.date_precision == "inherited"
      assert m.played_at == ~U[2008-02-06 00:00:00Z]
    end

    test "parse_page/1 skips unplayed matches instead of failing the page", %{page: page} do
      assert [%{key: "wW21Bs58Sa_M3", reason: :no_result}] = page.skipped
      assert length(page.matches) == 39
    end

    test "parse_page/1 prefers map results over opponent scores", %{page: page} do
      qf = find(page, "6NO2rUOrDw_R1M1")
      assert {qf.opponent1.name, qf.opponent2.name} == {"Jaedong", "Flash"}
      assert {qf.score1, qf.score2, qf.winner} == {1, 2, 2}
      assert Enum.map(qf.games, & &1.map) == ["Troy", "Fantasy II", "Katrina"]
    end
  end

  describe "inline edge cases" do
    defp page(body), do: Match2.parse_page("==Results==\n" <> body)

    test "parse_page/1 with p1= opponents, links and per-map races" do
      result =
        page("""
        {{Matchlist|id=X|M1header=Final
        |M1={{Match|bestof=3|date=2010-05-01 18:00 {{Abbr/KST}}
          |opponent1={{1Opponent|p1=Flash|p1race=t|link=Flash (Korean player)}}
          |opponent2={{1Opponent|p1=Ruby|p1race=r}}
          |map1={{Map|map=[[Python]]|winner=1|race2=z}}
          |map2={{Map|map=Destination|winner=1|race2=p}}
        }}
        }}
        """)

      assert [m] = result.matches

      assert m.opponent1 == %{
               name: "Flash",
               page: "Flash (Korean player)",
               race: "T",
               score: nil,
               win: nil
             }

      assert m.opponent2.race == "R"
      assert [%{map: "Python", race2: "Z"}, %{map: "Destination", race2: "P"}] = m.games
      assert m.round == "Final"
      assert m.played_at == ~U[2010-05-01 09:00:00Z]
    end

    test "parse_page/1 treats opponent score W/FF as a walkover" do
      result =
        page("""
        {{Matchlist|id=W
        |M1={{Match|opponent1={{1Opponent|A|score=FF}}|opponent2={{1Opponent|B|score=W}}}}
        }}
        """)

      assert [%{walkover: true, winner: 2, games: []}] = result.matches
    end

    test "parse_page/1 without any date leaves played_at nil" do
      result =
        page("""
        {{Matchlist|id=N
        |M1={{Match|opponent1={{1Opponent|A}}|opponent2={{1Opponent|B}}|map1={{Map|map=X|winner=2}}}}
        }}
        """)

      assert [%{played_at: nil, date_precision: nil, winner: 2}] = result.matches
    end

    test "parse_page/1 falls back to the infobox start date" do
      result =
        Match2.parse_page("""
        {{Infobox league
        |name=Test Cup
        |sdate=2012-03-04
        }}
        {{Matchlist|id=T
        |M1={{Match|opponent1={{1Opponent|A}}|opponent2={{1Opponent|B}}|map1={{Map|map=X|winner=1}}}}
        }}
        """)

      assert [%{played_at: ~U[2012-03-04 00:00:00Z], date_precision: "tournament"}] =
               result.matches
    end

    test "parse_page/1 reports TBD opponents and keeps going" do
      result =
        page("""
        {{Bracket|Bracket/2|id=B
        |R1M1={{Match|opponent1={{1Opponent|TBD}}|opponent2={{1Opponent|B}}}}
        |R1M2={{Match|opponent1={{1Opponent|C}}|opponent2={{1Opponent|D}}|map1={{Map|map=X|winner=1}}}}
        }}
        """)

      assert [%{key: "B_R1M1", reason: :tbd_opponent}] = result.skipped
      assert [%{key: "B_R1M2"}] = result.matches
    end

    test "parse_page/1 skips team opponents instead of reading them as players" do
      result =
        page("""
        {{Matchlist|id=P
        |M1={{Match|opponent1={{TeamOpponent|kt}}|opponent2={{TeamOpponent|skt}}|map1={{Map|map=X|winner=1}}}}
        }}
        """)

      assert result.matches == []
      assert [%{key: "P_M1", reason: :unsupported_opponent}] = result.skipped
    end

    test "parse_page/1 ignores matches inside HTML comments" do
      result =
        page("""
        {{Matchlist|id=C
        <!-- |M1={{Match|opponent1={{1Opponent|A}}|opponent2={{1Opponent|B}}|map1={{Map|map=X|winner=1}}}} -->
        }}
        """)

      assert result.matches == []
    end

    test "parse_datetime/1 handles month names with times" do
      assert Match2.parse_datetime("September 2, 2018 - 19:00 {{Abbr/KST}}") ==
               {~U[2018-09-02 10:00:00Z], "minute"}

      assert Match2.parse_datetime("TBA") == nil
    end
  end
end
