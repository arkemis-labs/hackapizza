defmodule Hackapizza.Agent.Jabba do
  use GenServer
  alias Arke.QueryManager
  alias Hackapizza.Rag.Retrieve
  alias Hackapizza.Agent.Guido

  @clusters ["dish"]
  @project_id :jabba_advisor

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts ++ [name: __MODULE__])
  end

  def query_menu(query) do
    GenServer.call(__MODULE__, {:query_menu, query})
  end

  def ask_agents(query, agents) do
    GenServer.call(__MODULE__, {:ask_agents, query, agents})
  end

  # Server Callbacks

  @impl true
  def init(:ok) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:query_menu, query}, _from, state) do
    results = jabba_work(query)
    {:reply, results, state}
  end

  def jabba_work(query) do
    # query =
    #   Guido.check_distance(query)
    #   |> enrich_query_with_distance(query)

    dataset =
      Retrieve.retrieve_data(query, @clusters)
      |> parse_dishes()

    IO.inspect(query)

    case Hackapizza.WatsonX.generate_result(query, dataset, max_tokens: 16000) do
      {:ok, %{"names" => []} }->
        {:ok, %{"names" => res}} = Hackapizza.WatsonX.generate_spicy_result(query, dataset, max_tokens: 16000)
        res

      {:ok, %{"names" => response} }->
        response

      _ ->
        [""]
    end
  end

  defp enrich_query_with_distance(:bruh, query), do: query

  defp enrich_query_with_distance({:ok, planet_list}, query),
    do: "#{query} filtra per pianeti #{Enum.join(planet_list, ", ")}"

  defp enrich_query_with_distance(_, query), do: query

  defp enrich_query_with_data(data, query) do
    """
    Filtra il <DATASET> a seconda delle condizioni specificate in <QUERY> e ritorna la lista dei nomi dei piatti filtrata

    <DATASET>
      #{data}
    </DATASET>

    <QUERY>
     #{query}
    </QUERY>
    """
  end

  defp parse_dishes(dishes) do
    Enum.reduce(
      dishes,
      [],
      fn dish, acc ->
        chef = QueryManager.get_by(project: @project_id, id: dish.data.link_chef)
        restaurant = QueryManager.get_by(project: @project_id, id: chef.data.link_restaurant)
        planet = QueryManager.get_by(project: @project_id, id: restaurant.data.link_planet)

        [
          # to_string(dish.id),
          [
            "nome: " <> dish.data.name,
            "ingredienti: " <> format_field(dish.data.ingredients),
            "tecniche: " <> format_field(dish.data.techniques),
            "pianeta: " <> planet.data.name,
            "ristorante: " <> restaurant.data.name,
            "chef: " <> chef.data.full_name,
            "regime alimentare: " <> (dish.data.cult || "")
          ]
          |> Enum.join("; ")
          | acc
        ]
      end
    )

    # Enum.reduce(
    #   dishes,
    #   "",
    #   fn dish, acc ->
    #     chef = QueryManager.get_by(project: @project_id, id: dish.data.link_chef)
    #     restaurant = QueryManager.get_by(project: @project_id, id: chef.data.link_restaurant)
    #     planet = QueryManager.get_by(project: @project_id, id: restaurant.data.link_planet)

    #     str =
    #       [
    #         # to_string(dish.id),
    #         "nome: " <> dish.data.name,
    #         "ingredienti: " <> format_field(dish.data.ingredients),
    #         "tecniche: " <> format_field(dish.data.techniques),
    #         "pianeta: " <> planet.data.name,
    #         "ristorante: " <> restaurant.data.name,
    #         "chef: " <> chef.data.full_name,
    #         "regime alimentare: " <> (dish.data.cult || "")
    #       ]
    #       |> Enum.join(";")

    #     """
    #     #{str}
    #     ###
    #     #{acc}
    #     """
    #   end
    # )
  end

  defp format_field(field) when is_list(field),
    do: Enum.reduce(field, "", fn f, acc -> "#{format_field(f)}, #{acc}" end)

  defp format_field(field) when is_map(field),
    do: Enum.map_join(field, " ", fn {k, v} -> "#{parse_key(k)} #{v}" end)

  defp format_field(field) when is_binary(field), do: field
  defp format_field(_), do: ""

  defp parse_key("level"), do: "Grado"
  defp parse_key("type"), do: "licenza"
  defp parse_key(other), do: other
end
