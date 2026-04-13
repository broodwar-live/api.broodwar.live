defmodule Broodwar.Pagination do
  @moduledoc """
  Offset-based pagination for Ecto queries.
  """
  import Ecto.Query

  @default_per_page 50
  @max_per_page 200

  def paginate(query, opts) do
    page = max(opts[:page] || 1, 1)
    per_page = opts[:per_page] |> parse_per_page()
    offset = (page - 1) * per_page

    query
    |> limit(^per_page)
    |> offset(^offset)
  end

  def pagination_meta(opts) do
    page = max(opts[:page] || 1, 1)
    per_page = opts[:per_page] |> parse_per_page()

    %{page: page, per_page: per_page}
  end

  defp parse_per_page(nil), do: @default_per_page
  defp parse_per_page(n) when is_integer(n), do: min(max(n, 1), @max_per_page)
  defp parse_per_page(_), do: @default_per_page
end
