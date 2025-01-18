defmodule HackapizzaWeb.PageController do
  use HackapizzaWeb, :controller

  alias ArkeServer.ResponseManager

  def home(conn, _params) do

    ResponseManager.send_resp(conn, 200, nil)
  end
end
