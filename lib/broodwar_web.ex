defmodule BroodwarWeb do
  @moduledoc """
  The entrypoint for defining the JSON API web interface.
  """

  def static_paths, do: ~w()

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: BroodwarWeb.Endpoint,
        router: BroodwarWeb.Router,
        statics: BroodwarWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
