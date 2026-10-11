defmodule BroodwarWeb.Api.Params do
  @moduledoc "Query-parameter helpers shared by API controllers."

  @doc "Pagination options from `page` / `per_page` (see Broodwar.Pagination)."
  def pagination(params) do
    [page: int(params["page"]) || 1, per_page: int(params["per_page"]) || 50]
  end

  @doc "Parses a positive integer parameter; `nil` if absent or invalid."
  def int(nil), do: nil
  def int(n) when is_integer(n), do: n

  def int(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> n
      _ -> nil
    end
  end

  def int(_), do: nil
end
