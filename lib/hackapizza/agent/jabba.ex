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

    query =
      Retrieve.retrieve_data(query, @clusters)
      # |> exclude_data(query)
      |> parse_dishes()
      |> enrich_query_with_data(query)

    IO.inspect(query)

    case Hackapizza.WatsonX.generate(query,
           parameters: %{"max_new_tokens" => 1000},
           max_tokens: 16000
         ) do
      {:ok, response} ->
        IO.inspect(response)
        response["results"] |> List.first() |> Map.get("generated_text")

      _ ->
        ""
    end
  end

  defp enrich_query_with_distance(:bruh, query), do: query

  defp enrich_query_with_distance({:ok, planet_list}, query),
    do: "#{query} filtra per pianeti #{Enum.join(planet_list, ", ")}"

  defp enrich_query_with_distance(_, query), do: query

  defp enrich_query_with_data(data, query) do
    """
    Return only the comma-separated list of matching IDs, with no additional text or formatting. Example output: abc1-23,de-f4-56,gh-i78-9

    <DATASET_STRUCTURE>
    - id: UUID
    - dish_name: string
    - ingredients: semicolons-separated list
    - cooking_methods: semicolons-separated list
    - origin_planet: string
    - restaurant_category: string
    - chef_name: string
    </DATASET_STRUCTURE>

    <FILTER_RULES>
    - Each field is separated by commas
    - Return only the ID if ALL conditions are met
    </FILTER_RULES>

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
      "id,piatto,ingredienti,tecniche,pianeta,ristorante,chef,regimi alimentari",
      fn dish, acc ->
        chef = QueryManager.get_by(project: @project_id, id: dish.data.link_chef)
        restaurant = QueryManager.get_by(project: @project_id, id: chef.data.link_restaurant)
        planet = QueryManager.get_by(project: @project_id, id: restaurant.data.link_planet)

        str =
          [
            to_string(dish.id),
            dish.data.name,
            format_field(dish.data.ingredients),
            format_field(dish.data.techniques),
            planet.data.name,
            restaurant.data.name,
            chef.data.full_name,
            dish.data.cult || ""
          ]
          |> Enum.join(",")

        """
        #{str}
        #{acc}
        """
      end
    )
  end

  defp format_field(field) when is_list(field),
    do: Enum.reduce(field, "", fn f, acc -> "#{format_field(f)}; #{acc}" end)

  defp format_field(field) when is_map(field),
    do: Enum.map_join(field, " ", fn {k, v} -> "#{parse_key(k)} #{v}" end)

  defp format_field(field) when is_binary(field), do: field
  defp format_field(_), do: ""

  defp parse_key("level"), do: "Livello"
  defp parse_key("type"), do: "licenza"
  defp parse_key(other), do: other
end
