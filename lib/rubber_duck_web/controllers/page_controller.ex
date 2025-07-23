defmodule RubberDuckWeb.PageController do
  use RubberDuckWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
