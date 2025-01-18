defmodule HackapizzaWeb.ErrorViewTest do
  use HackapizzaWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.View

  test "renders 404.json" do
    assert render_to_string(HackapizzaWeb.ErrorView, "404.json", [])  == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500.json" do
    assert render_to_string(HackapizzaWeb.ErrorView, "500.json", []) ==
      %{errors: %{detail: "Internal Server Error"}}
  end
end
