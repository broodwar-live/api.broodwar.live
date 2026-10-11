defmodule BroodwarWeb.Api.HealthControllerTest do
  use BroodwarWeb.ConnCase

  test "show returns ok when the database is reachable", %{conn: conn} do
    conn = get(conn, ~p"/api/health")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
