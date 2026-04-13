defmodule Broodwar.Tournaments.Data do
  @moduledoc """
  Static reference data for major StarCraft: Brood War tournament series.
  """

  @series [
    %{
      slug: "asl",
      name: "AfreecaTV StarCraft League",
      name_ko: "아프리카TV 스타크래프트 리그",
      short_name: "ASL",
      organizer: "AfreecaTV / SOOP",
      status: :active,
      description: "The premier individual StarCraft: Brood War league, successor to the original Starleagues. Broadcast on AfreecaTV (now SOOP) since 2016, ASL has become the definitive modern BW tournament with top Korean pros competing for the championship.",
      description_ko: "스타크래프트: 브루드 워의 최고 개인 리그로, 기존 스타리그의 후계자입니다. 2016년부터 아프리카TV(현 SOOP)에서 방송되며, ASL은 한국 최고의 프로게이머들이 우승을 다투는 현대 BW의 대표 대회가 되었습니다.",
      format: "Individual",
      region: "South Korea",
      seasons: [
        %{season: 21, year: 2026, status: :live, winner: nil, runner_up: nil, prize_pool: "₩50,000,000"},
        %{season: 20, year: 2025, status: :completed, winner: "Flash", runner_up: "Rain", prize_pool: "₩50,000,000"},
        %{season: 19, year: 2025, status: :completed, winner: "Rain", runner_up: "Snow", prize_pool: "₩50,000,000"},
        %{season: 18, year: 2024, status: :completed, winner: "Snow", runner_up: "Soulkey", prize_pool: "₩50,000,000"},
        %{season: 17, year: 2024, status: :completed, winner: "Flash", runner_up: "Rain", prize_pool: "₩50,000,000"},
        %{season: 16, year: 2023, status: :completed, winner: "Rain", runner_up: "Flash", prize_pool: "₩50,000,000"},
        %{season: 15, year: 2023, status: :completed, winner: "Snow", runner_up: "Soulkey", prize_pool: "₩40,000,000"},
        %{season: 14, year: 2022, status: :completed, winner: "Rain", runner_up: "Mini", prize_pool: "₩40,000,000"},
        %{season: 13, year: 2022, status: :completed, winner: "Snow", runner_up: "Rain", prize_pool: "₩40,000,000"},
        %{season: 12, year: 2021, status: :completed, winner: "Rain", runner_up: "Flash", prize_pool: "₩40,000,000"},
        %{season: 11, year: 2021, status: :completed, winner: "Flash", runner_up: "Sharp", prize_pool: "₩40,000,000"},
        %{season: 10, year: 2020, status: :completed, winner: "Mini", runner_up: "Rush", prize_pool: "₩40,000,000"},
        %{season: 9, year: 2020, status: :completed, winner: "Flash", runner_up: "Mini", prize_pool: "₩40,000,000"},
        %{season: 8, year: 2019, status: :completed, winner: "Rain", runner_up: "Flash", prize_pool: "₩40,000,000"},
        %{season: 7, year: 2019, status: :completed, winner: "Flash", runner_up: "Jaedong", prize_pool: "₩40,000,000"},
        %{season: 6, year: 2018, status: :completed, winner: "Flash", runner_up: "Soulkey", prize_pool: "₩40,000,000"},
        %{season: 5, year: 2018, status: :completed, winner: "Rain", runner_up: "Flash", prize_pool: "₩35,000,000"},
        %{season: 4, year: 2017, status: :completed, winner: "Rain", runner_up: "EffOrt", prize_pool: "₩35,000,000"},
        %{season: 3, year: 2017, status: :completed, winner: "Flash", runner_up: "Jaedong", prize_pool: "₩35,000,000"},
        %{season: 2, year: 2017, status: :completed, winner: "Flash", runner_up: "Bisu", prize_pool: "₩35,000,000"},
        %{season: 1, year: 2016, status: :completed, winner: "Flash", runner_up: "Bisu", prize_pool: "₩35,000,000"}
      ]
    },
    %{
      slug: "bsl",
      name: "Brood War Starleague",
      name_ko: "브루드 워 스타리그",
      short_name: "BSL",
      organizer: "BSL Team",
      status: :active,
      description: "The largest international Brood War tournament series, featuring top players from Europe, Americas, and Korea. BSL has grown into a major community-run league with substantial prize pools and high production quality.",
      description_ko: "유럽, 아메리카, 한국의 최고 선수들이 참가하는 최대 규모의 국제 브루드 워 토너먼트 시리즈입니다. BSL은 상당한 상금과 높은 제작 품질을 갖춘 주요 커뮤니티 운영 리그로 성장했습니다.",
      format: "Individual",
      region: "International",
      seasons: [
        %{season: 20, year: 2026, status: :live, winner: nil, runner_up: nil, prize_pool: "$5,000"},
        %{season: 19, year: 2025, status: :completed, winner: "Dewalt", runner_up: "Sziky", prize_pool: "$5,000"},
        %{season: 18, year: 2025, status: :completed, winner: "Dewalt", runner_up: "Scan", prize_pool: "$4,000"},
        %{season: 17, year: 2024, status: :completed, winner: "Dewalt", runner_up: "Scan", prize_pool: "$4,000"}
      ]
    },
    %{
      slug: "osl",
      name: "OnGameNet Starleague",
      name_ko: "온게임넷 스타리그",
      short_name: "OSL",
      organizer: "OnGameNet",
      status: :retired,
      description: "The original premier Starleague (2000–2012), the most prestigious individual BW tournament of the golden era. Held at Yongsan e-Sports Stadium with massive live audiences, OSL champions are considered the greatest players in BW history.",
      description_ko: "오리지널 프리미어 스타리그(2000-2012)로, 황금기 BW의 가장 권위 있는 개인 대회입니다. 용산 e스포츠 스타디움에서 대규모 관중과 함께 열렸으며, OSL 우승자는 BW 역사상 최고의 선수로 인정받습니다.",
      format: "Individual",
      region: "South Korea",
      seasons: [
        %{season: 13, year: 2012, status: :completed, winner: "Fantasy", runner_up: "Bisu", prize_pool: "₩100,000,000"},
        %{season: 12, year: 2011, status: :completed, winner: "Jangbi", runner_up: "Stork", prize_pool: "₩100,000,000"},
        %{season: 11, year: 2010, status: :completed, winner: "Flash", runner_up: "Jangbi", prize_pool: "₩100,000,000"},
        %{season: 10, year: 2009, status: :completed, winner: "Jaedong", runner_up: "Flash", prize_pool: "₩100,000,000"},
        %{season: 9, year: 2008, status: :completed, winner: "Flash", runner_up: "Stork", prize_pool: "₩100,000,000"},
        %{season: 8, year: 2007, status: :completed, winner: "Bisu", runner_up: "Savior", prize_pool: "₩70,000,000"},
        %{season: 7, year: 2006, status: :completed, winner: "Savior", runner_up: "NaDa", prize_pool: "₩70,000,000"}
      ]
    },
    %{
      slug: "msl",
      name: "MBC Game Starleague",
      name_ko: "MBC게임 스타리그",
      short_name: "MSL",
      organizer: "MBC Game",
      status: :retired,
      description: "The second major individual Starleague (2001–2012), running alongside OSL. Known for its intense competition and iconic moments, MSL was crucial in establishing BW as a major esport in South Korea.",
      description_ko: "OSL과 함께 운영된 두 번째 주요 개인 스타리그(2001-2012)입니다. 치열한 경쟁과 상징적인 순간들로 유명하며, MSL은 한국에서 BW를 주요 e스포츠로 자리매김하는 데 핵심적인 역할을 했습니다.",
      format: "Individual",
      region: "South Korea",
      seasons: [
        %{season: 13, year: 2012, status: :completed, winner: "Rain", runner_up: "hero", prize_pool: "₩60,000,000"},
        %{season: 12, year: 2011, status: :completed, winner: "DongRaeGu", runner_up: "July", prize_pool: "₩60,000,000"},
        %{season: 11, year: 2010, status: :completed, winner: "Flash", runner_up: "Calm", prize_pool: "₩60,000,000"},
        %{season: 10, year: 2009, status: :completed, winner: "Flash", runner_up: "Jaedong", prize_pool: "₩60,000,000"},
        %{season: 9, year: 2008, status: :completed, winner: "Jaedong", runner_up: "EffOrt", prize_pool: "₩60,000,000"}
      ]
    },
    %{
      slug: "ksl",
      name: "Korean StarCraft League",
      name_ko: "코리안 스타크래프트 리그",
      short_name: "KSL",
      organizer: "Blizzard Korea",
      status: :retired,
      description: "Blizzard Korea's official BW league (2018–2019), launched alongside StarCraft: Remastered. While short-lived, KSL brought modern production values and attracted returning pros.",
      description_ko: "스타크래프트: 리마스터와 함께 출시된 블리자드 코리아의 공식 BW 리그(2018-2019)입니다. 짧은 기간이었지만, KSL은 현대적인 제작 품질을 선보이며 복귀하는 프로게이머들을 끌어모았습니다.",
      format: "Individual",
      region: "South Korea",
      seasons: [
        %{season: 3, year: 2019, status: :completed, winner: "Rain", runner_up: "Flash", prize_pool: "₩30,000,000"},
        %{season: 2, year: 2019, status: :completed, winner: "Last", runner_up: "Mini", prize_pool: "₩30,000,000"},
        %{season: 1, year: 2018, status: :completed, winner: "Rain", runner_up: "EffOrt", prize_pool: "₩30,000,000"}
      ]
    },
    %{
      slug: "soop-starleague",
      name: "SOOP Starleague",
      name_ko: "숲 스타리그",
      short_name: "SSL",
      organizer: "SOOP",
      status: :active,
      description: "SOOP's team/invitational format BW events, complementing ASL with a different competitive format and bringing variety to the modern tournament scene.",
      description_ko: "SOOP의 팀/초청 형식 BW 이벤트로, ASL을 보완하며 다양한 경쟁 형식으로 현대 토너먼트 씬에 다양성을 더합니다.",
      format: "Team/Invitational",
      region: "South Korea",
      seasons: []
    }
  ]

  def series, do: @series

  def series(slug) do
    Enum.find(@series, fn s -> s.slug == slug end)
  end

  def active_series do
    Enum.filter(@series, fn s -> s.status == :active end)
  end

  def retired_series do
    Enum.filter(@series, fn s -> s.status == :retired end)
  end

  def live_seasons do
    @series
    |> Enum.flat_map(fn s ->
      s.seasons
      |> Enum.filter(fn season -> season.status == :live end)
      |> Enum.map(fn season -> Map.merge(season, %{series: s}) end)
    end)
  end

  def all_champions do
    @series
    |> Enum.flat_map(fn s ->
      s.seasons
      |> Enum.filter(fn season -> season.winner != nil end)
      |> Enum.map(fn season -> Map.merge(season, %{series_name: s.short_name, series_slug: s.slug}) end)
    end)
    |> Enum.sort_by(fn s -> {-s.year, -s.season} end)
  end

  def champion_counts do
    all_champions()
    |> Enum.group_by(fn s -> s.winner end)
    |> Enum.map(fn {name, wins} -> %{name: name, count: length(wins)} end)
    |> Enum.sort_by(fn c -> -c.count end)
  end
end
