defmodule Broodwar.Ingestion.Wikitext do
  @moduledoc """
  Minimal MediaWiki template parser.

  Only what the Liquipedia ingestion needs: find templates, split their
  parameters at top-level `|` (respecting nested `{{...}}` and `[[...]]`),
  and clean display text. It is not a general wikitext renderer.
  """

  @type param :: {String.t(), String.t()}
  @type template :: %{name: String.t(), params: [param()], offset: non_neg_integer()}

  @doc "Removes `<!-- ... -->` comments."
  @spec strip_comments(String.t()) :: String.t()
  def strip_comments(text), do: Regex.replace(~r/<!--.*?-->/s, text, "")

  @doc """
  Returns the top-level templates of `text` in order, each with its byte
  `offset`. Unterminated templates end the scan.
  """
  @spec templates(String.t()) :: [template()]
  def templates(text), do: do_templates(text, 0, [])

  defp do_templates(text, base, acc) do
    case :binary.match(text, "{{") do
      :nomatch ->
        Enum.reverse(acc)

      {pos, 2} ->
        rest = binary_part(text, pos + 2, byte_size(text) - pos - 2)

        case split(rest) do
          {:ok, parts, remaining} ->
            consumed = byte_size(text) - byte_size(remaining)
            template = build(parts, base + pos)
            do_templates(remaining, base + consumed, [template | acc])

          :error ->
            Enum.reverse(acc)
        end
    end
  end

  @doc """
  Parses a single template value such as `{{1Opponent|Flash|race=t}}`.
  Returns `nil` if `value` does not start with a template.
  """
  @spec parse_template(String.t() | nil) :: template() | nil
  def parse_template(nil), do: nil

  def parse_template(value) do
    case String.trim_leading(value) do
      "{{" <> rest ->
        case split(rest) do
          {:ok, parts, _rest} -> build(parts, 0)
          :error -> nil
        end

      _ ->
        nil
    end
  end

  @doc "Looks up a named parameter (first occurrence wins)."
  @spec get(template(), String.t()) :: String.t() | nil
  def get(%{params: params}, key) do
    Enum.find_value(params, fn
      {^key, value} -> value
      _ -> nil
    end)
  end

  @doc "Returns the first non-blank value among `keys`."
  @spec get_any(template(), [String.t()]) :: String.t() | nil
  def get_any(template, keys) do
    Enum.find_value(keys, fn key ->
      case get(template, key) do
        value when value in [nil, ""] -> nil
        value -> value
      end
    end)
  end

  @doc """
  Strips markup from display text: `[[Page|Label]]` → `Label`,
  `{{Template|X}}` → `X`, bold/italic quotes, and surrounding whitespace.
  """
  @spec clean(String.t() | nil) :: String.t() | nil
  def clean(nil), do: nil

  def clean(text) do
    text
    |> replace_templates()
    |> then(&Regex.replace(~r/\[\[(?:[^\]|]*\|)?([^\]]*)\]\]/, &1, "\\1"))
    |> String.replace(~r/'{2,}/, "")
    |> String.trim()
  end

  # {{Stage|Round of 24}} -> "Round of 24"; templates without a positional
  # argument are dropped.
  defp replace_templates(text) do
    text
    |> templates()
    |> Enum.reverse()
    |> Enum.reduce(text, fn %{offset: offset} = template, acc ->
      {:ok, _parts, rest} = split(binary_part(acc, offset + 2, byte_size(acc) - offset - 2))
      len = byte_size(acc) - offset - byte_size(rest)
      replacement = get(template, "1") || ""

      binary_part(acc, 0, offset) <>
        replacement <> binary_part(acc, offset + len, byte_size(acc) - offset - len)
    end)
  end

  defp build([name | args], offset) do
    {params, _n} =
      Enum.reduce(args, {[], 1}, fn arg, {acc, n} ->
        case named(arg) do
          {key, value} -> {[{key, value} | acc], n}
          nil -> {[{Integer.to_string(n), String.trim(arg)} | acc], n + 1}
        end
      end)

    %{name: String.trim(name), params: Enum.reverse(params), offset: offset}
  end

  # "key=value" where the key part contains no nested markup.
  defp named(arg) do
    with [key, value] <- :binary.split(arg, "="),
         false <- String.contains?(key, ["{{", "[[", "}}"]) do
      {String.trim(key), String.trim(value)}
    else
      _ -> nil
    end
  end

  # Splits the inside of a template (text just after "{{") into its
  # top-level parts. Returns the text after the closing "}}".
  defp split(text), do: split(text, 0, 0, [], [])

  defp split(<<"}}", rest::binary>>, 0, 0, cur, parts),
    do: {:ok, Enum.reverse([IO.iodata_to_binary(cur) | parts]), rest}

  defp split(<<"{{", rest::binary>>, d, l, cur, parts),
    do: split(rest, d + 1, l, [cur, "{{"], parts)

  defp split(<<"}}", rest::binary>>, d, l, cur, parts) when d > 0,
    do: split(rest, d - 1, l, [cur, "}}"], parts)

  defp split(<<"[[", rest::binary>>, d, l, cur, parts),
    do: split(rest, d, l + 1, [cur, "[["], parts)

  defp split(<<"]]", rest::binary>>, d, l, cur, parts) when l > 0,
    do: split(rest, d, l - 1, [cur, "]]"], parts)

  defp split(<<"|", rest::binary>>, 0, 0, cur, parts),
    do: split(rest, 0, 0, [], [IO.iodata_to_binary(cur) | parts])

  defp split(<<c, rest::binary>>, d, l, cur, parts),
    do: split(rest, d, l, [cur, c], parts)

  defp split(<<>>, _d, _l, _cur, _parts), do: :error
end
