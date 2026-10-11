defmodule BroodwarWeb.ErrorJSONTest do
  use BroodwarWeb.ConnCase, async: true

  test "render/2 404 uses the standard error shape" do
    assert BroodwarWeb.ErrorJSON.render("404.json", %{}) ==
             %{error: %{code: "NOT_FOUND", message: "Not Found"}}
  end

  test "render/2 413 uses the standard error shape" do
    assert BroodwarWeb.ErrorJSON.render("413.json", %{}) ==
             %{error: %{code: "REQUEST_ENTITY_TOO_LARGE", message: "Request Entity Too Large"}}
  end
end
