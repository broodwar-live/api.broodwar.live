defmodule Broodwar.Ingestion.Liquipedia do
  @moduledoc """
  Client for the Liquipedia MediaWiki API.

  Fetches StarCraft: Brood War tournament, player, and match data
  from Liquipedia's public MediaWiki API.

  Rate limited to 1 request per 2 seconds as per Liquipedia's terms.
  """

  @base_url "https://liquipedia.net/starcraft/api.php"
  @user_agent "broodwar.live/0.1 (https://github.com/broodwar-live; community@broodwar.live)"

  @doc """
  Fetches raw wikitext content for a page.
  """
  def get_page(title) do
    params = %{
      action: "query",
      titles: title,
      prop: "revisions",
      rvprop: "content",
      rvslots: "main",
      format: "json"
    }

    case api_request(params) do
      {:ok, %{"query" => %{"pages" => pages}}} ->
        page = pages |> Map.values() |> List.first()

        case page do
          %{"revisions" => [%{"slots" => %{"main" => %{"*" => content}}} | _]} ->
            {:ok, content}

          _ ->
            {:error, :page_not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches parsed HTML for a page (rate limited to 1 req/30s).
  """
  def get_parsed_page(title) do
    params = %{
      action: "parse",
      page: title,
      format: "json",
      prop: "text|sections"
    }

    case api_request(params) do
      {:ok, %{"parse" => data}} -> {:ok, data}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Lists pages in a category. Returns a list of page titles.
  """
  def list_category(category, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    params = %{
      action: "query",
      list: "categorymembers",
      cmtitle: "Category:#{category}",
      cmlimit: limit,
      format: "json"
    }

    case api_request(params) do
      {:ok, %{"query" => %{"categorymembers" => members}}} ->
        {:ok, Enum.map(members, & &1["title"])}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches a tournament page and parses the Infobox league template.
  Returns a map of tournament metadata.
  """
  def fetch_tournament(page_title) do
    with {:ok, wikitext} <- get_page(page_title) do
      info = parse_infobox_league(wikitext)
      matches = parse_all_matches(wikitext)
      {:ok, Map.put(info, :matches, matches)}
    end
  end

  @doc """
  Fetches a list of all ASL season pages.
  """
  def fetch_asl_seasons do
    with {:ok, wikitext} <- get_page("AfreecaTV_StarCraft_League") do
      # Parse season links from the series overview page
      {:ok, parse_season_links(wikitext, "AfreecaTV")}
    end
  end

  # -- Wikitext Parsing --

  @doc false
  def parse_infobox_league(wikitext) do
    case extract_template(wikitext, "Infobox league") do
      nil ->
        %{}

      template_content ->
        fields = parse_template_fields(template_content)

        placements = extract_bracket_placements(wikitext)

        %{
          name: fields["name"],
          series: fields["series"],
          abbreviation: fields["abbreviation"],
          organizer: fields["organizer"],
          type: fields["type"],
          prize_pool: fields["prizepool"],
          prize_pool_usd: parse_prize_usd(fields["prizepool"]),
          local_currency: fields["localcurrency"],
          country: fields["country"],
          city: fields["city"],
          start_date: fields["sdate"],
          end_date: fields["edate"],
          format: fields["format"],
          edition: fields["edition"],
          player_count: parse_int(fields["player_number"]),
          terran_count: parse_int(fields["terran_number"]),
          protoss_count: parse_int(fields["protoss_number"]),
          zerg_count: parse_int(fields["zerg_number"]),
          tier: fields["liquipediatier"],
          first_place: placements[:first] || clean_player_name(fields["idfirst"]),
          first_place_race: fields["racefirst"],
          second_place: placements[:second] || clean_player_name(fields["idsecond"]),
          second_place_race: fields["racesecond"],
          third_place: clean_player_name(fields["idthird"]),
          fourth_place: clean_player_name(fields["idfourth"]),
          maps:
            1..7
            |> Enum.map(fn i -> fields["map#{i}"] end)
            |> Enum.reject(&is_nil/1)
            |> Enum.reject(&(&1 == "")),
          previous: fields["previous"],
          next: fields["next"],
          participants: extract_participants(wikitext),
          raw_fields: fields
        }
    end
  end

  @doc """
  Extracts all matches from a tournament wikitext page.
  Returns a list of match maps with opponents, map results, dates, and context.
  """
  def parse_all_matches(wikitext) do
    # Split the wikitext into lines for context tracking
    # Find each {{Match block and parse it
    extract_match_blocks(wikitext)
    |> Enum.map(fn {context, block} ->
      fields = parse_template_fields(block)

      opponent1 = extract_opponent(fields["opponent1"])
      opponent2 = extract_opponent(fields["opponent2"])

      maps =
        1..9
        |> Enum.map(fn i -> parse_map_result(fields["map#{i}"]) end)
        |> Enum.reject(&is_nil/1)

      p1_wins = Enum.count(maps, fn m -> m.winner == 1 end)
      p2_wins = Enum.count(maps, fn m -> m.winner == 2 end)

      winner =
        cond do
          p1_wins > p2_wins -> opponent1
          p2_wins > p1_wins -> opponent2
          true -> nil
        end

      %{
        context: context,
        date: clean_date(fields["date"]),
        best_of: parse_int(fields["bestof"]),
        opponent1: opponent1,
        opponent2: opponent2,
        score: "#{p1_wins}-#{p2_wins}",
        winner: winner,
        maps: maps,
        vod: fields["vod"]
      }
    end)
    |> Enum.reject(fn m -> is_nil(m.opponent1) or is_nil(m.opponent2) end)
  end

  defp extract_match_blocks(wikitext) do
    # Track current context (group name, round) as we scan
    lines = String.split(wikitext, "\n")

    {matches, _ctx} =
      Enum.reduce(lines, {[], %{section: nil, round: nil}}, fn line, {acc, ctx} ->
        trimmed = String.trim(line)

        # Track section headers (===Group A===, ===Bracket===)
        ctx =
          case Regex.run(~r/^===+\s*(.+?)\s*===+$/, trimmed) do
            [_, section] -> %{ctx | section: section}
            _ -> ctx
          end

        # Track matchlist titles
        ctx =
          case Regex.run(~r/\{\{Matchlist\|.*?title=([^|}]+)/, trimmed) do
            [_, title] -> %{ctx | section: String.trim(title)}
            _ -> ctx
          end

        # Track round headers (R1M1header=Quarterfinals)
        ctx =
          case Regex.run(~r/\|(?:M\d+header|R\d+M\d+header)=(.+)$/, trimmed) do
            [_, round] -> %{ctx | round: String.trim(round)}
            _ -> ctx
          end

        # Track bracket round headers
        ctx =
          case Regex.run(~r/\|R\d+M\d+header=(.+)$/, trimmed) do
            [_, round] -> %{ctx | round: String.trim(round)}
            _ -> ctx
          end

        # Detect match start
        if String.contains?(trimmed, "={{Match") do
          context = [ctx.section, ctx.round] |> Enum.reject(&is_nil/1) |> Enum.join(" — ")
          # Collect the match block content
          {[{context, ""} | acc], ctx}
        else
          # Append line to current match block if we're in one
          case acc do
            [{context, block} | rest] when block != nil ->
              if String.starts_with?(trimmed, "}}") and not String.contains?(block, "opponent1") do
                # Empty/incomplete block, skip
                {rest, ctx}
              else
                {[{context, block <> "\n" <> line} | rest], ctx}
              end

            _ ->
              {acc, ctx}
          end
        end
      end)

    Enum.reverse(matches)
  end

  defp clean_date(nil), do: nil

  defp clean_date(date_str) do
    # Extract YYYY-MM-DD from strings like "2024-04-01 19:15 {{Abbr/KST}}"
    case Regex.run(~r/(\d{4}-\d{2}-\d{2})/, date_str) do
      [_, date] -> date
      _ -> date_str
    end
  end

  @doc false
  def extract_bracket_placements(wikitext) do
    # Find the highest round number in the bracket (finals)
    rounds = Regex.scan(~r/\|R(\d+)M1=\{\{Match/, wikitext)
    max_round = rounds |> Enum.map(fn [_, r] -> String.to_integer(r) end) |> Enum.max(fn -> 0 end)

    if max_round > 0 do
      # Extract the finals match block by splitting from R{max}M1 marker
      marker = "|R#{max_round}M1={{Match"

      case String.split(wikitext, marker, parts: 2) do
        [_, rest] ->
          # Take content until the next bracket marker or end of bracket
          match_block = rest |> String.split(~r/\n\|R\d+M\d+=|\n\}\}\n/, parts: 2) |> List.first("")

          # Extract opponents
          opponents = Regex.scan(~r/\{\{1Opponent\|([^}|]+)/, match_block)
          # Extract map winners
          map_wins = Regex.scan(~r/\{\{Map\|winner=(\d)/, match_block)
                     |> Enum.map(fn [_, w] -> String.to_integer(w) end)

          case opponents do
            [[_, p1], [_, p2] | _] ->
              p1_wins = Enum.count(map_wins, &(&1 == 1))
              p2_wins = Enum.count(map_wins, &(&1 == 2))

              if p1_wins >= p2_wins do
                %{first: String.trim(p1), second: String.trim(p2)}
              else
                %{first: String.trim(p2), second: String.trim(p1)}
              end

            _ ->
              %{}
          end

        _ ->
          %{}
      end
    else
      %{}
    end
  end

  @doc false
  def extract_participants(wikitext) do
    Regex.scan(~r/\{\{1Opponent\|([^}|]+)/, wikitext)
    |> Enum.map(fn [_, name] -> String.trim(name) end)
    |> Enum.uniq()
  end

  # -- Template extraction helpers --

  defp extract_template(wikitext, template_name) do
    # Match the opening of the template, then find balanced braces
    pattern = ~r/\{\{#{Regex.escape(template_name)}\s*\n/i

    case Regex.run(pattern, wikitext, return: :index) do
      [{start, len}] ->
        rest = String.slice(wikitext, (start + len)..-1//1)
        find_balanced_end(rest, 1, "")

      _ ->
        nil
    end
  end

  defp find_balanced_end(<<"}}", rest::binary>>, 1, acc), do: acc
  defp find_balanced_end(<<"}}", rest::binary>>, depth, acc), do: find_balanced_end(rest, depth - 1, acc <> "}}")
  defp find_balanced_end(<<"{{", rest::binary>>, depth, acc), do: find_balanced_end(rest, depth + 1, acc <> "{{")
  defp find_balanced_end(<<c::utf8, rest::binary>>, depth, acc), do: find_balanced_end(rest, depth, acc <> <<c::utf8>>)
  defp find_balanced_end("", _depth, acc), do: acc

  defp parse_template_fields(content) do
    content
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      case Regex.run(~r/^\s*\|([^=]+)=(.*)$/, String.trim(line)) do
        [_, key, value] ->
          Map.put(acc, String.trim(key), String.trim(value))

        _ ->
          acc
      end
    end)
  end

  defp extract_opponent(nil), do: nil

  defp extract_opponent(text) do
    case Regex.run(~r/\{\{1Opponent\|([^}|]+)/, text) do
      [_, name] -> String.trim(name)
      _ -> clean_player_name(text)
    end
  end

  defp parse_map_result(nil), do: nil

  defp parse_map_result(text) do
    case Regex.run(~r/\{\{Map\|.*?winner=(\d).*?map=([^}|]+)/, text) do
      [_, winner, map_name] ->
        %{winner: String.to_integer(winner), map: String.trim(map_name)}

      _ ->
        nil
    end
  end

  defp clean_player_name(nil), do: nil

  defp clean_player_name(text) do
    text
    |> String.replace(~r/\[\[.*?\|/, "")
    |> String.replace(~r/[\[\]]/, "")
    # Strip leftover template fields like |racefirst=t |flagfirst=kr
    |> String.replace(~r/\|[a-z]+=\S*/i, "")
    |> String.trim()
    |> case do
      "" -> nil
      name -> name
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(str) do
    case Integer.parse(String.trim(str)) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_prize_usd(nil), do: nil

  defp parse_prize_usd(text) do
    case Regex.run(~r/\$[\s]*([\d,]+)/, text) do
      [_, amount] -> amount |> String.replace(",", "") |> parse_int()
      _ -> nil
    end
  end

  defp parse_season_links(wikitext, series_prefix) do
    Regex.scan(~r/\[\[(#{Regex.escape(series_prefix)}[^\]]+)\]\]/, wikitext)
    |> Enum.map(fn [_, link] -> link |> String.split("|") |> List.first() end)
    |> Enum.uniq()
  end

  @doc """
  Fetches the image filename from a player's Liquipedia page infobox.
  """
  def fetch_player_image_filename(page_title) do
    with {:ok, wikitext} <- get_page(page_title) do
      case Regex.run(~r/\|image\s*=\s*(.+)$/m, wikitext) do
        [_, filename] -> {:ok, String.trim(filename)}
        _ -> {:error, :no_image}
      end
    end
  end

  @doc """
  Gets the actual URL for a Liquipedia image file.
  """
  def get_image_url(filename) do
    params = %{
      action: "query",
      titles: "File:#{filename}",
      prop: "imageinfo",
      iiprop: "url",
      format: "json"
    }

    case api_request(params) do
      {:ok, %{"query" => %{"pages" => pages}}} ->
        page = pages |> Map.values() |> List.first()

        case get_in(page, ["imageinfo", Access.at(0), "url"]) do
          nil -> {:error, :no_url}
          url -> {:ok, url}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Downloads an image from a URL and saves it to the given path.
  """
  def download_image(url, dest_path) do
    case Req.get(url,
           headers: [
             {"user-agent", @user_agent}
           ],
           max_redirects: 5,
           decode_body: false
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        File.mkdir_p!(Path.dirname(dest_path))
        File.write!(dest_path, body)
        {:ok, dest_path}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -- HTTP --

  defp api_request(params) do
    # Rate limit: sleep briefly to respect Liquipedia's 1 req/2s policy
    Process.sleep(2_100)

    case Req.get(@base_url,
           params: params,
           headers: [
             {"user-agent", @user_agent},
             {"accept-encoding", "gzip"}
           ],
           decode_body: :json
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
