defmodule BroodwarWeb.ErrorJSON do
  @moduledoc """
  Renders errors raised outside controllers (e.g. `Plug.Parsers` rejecting
  an oversized body, unmatched routes) in the standard API error shape.
  """

  def render(template, _assigns) do
    message = Phoenix.Controller.status_message_from_template(template)

    code =
      message
      |> String.upcase()
      |> String.replace(~r/[^A-Z0-9]+/, "_")
      |> String.trim("_")

    %{error: %{code: code, message: message}}
  end
end
