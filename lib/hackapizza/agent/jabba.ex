defmodule Hackapizza.Agent.Jabba do
  use GenServer
  require Logger
  alias Arke.QueryManager
  alias Hackapizza.Rag.Retrieve
  alias Hackapizza.Agent.Guido

  @clusters ["dish"]
  @project_id :jabba_advisor
  # 2 minutes timeout
  @default_timeout :timer.minutes(2)

  def start_link(opts \\ []) do
    Logger.info("Starting Jabba agent")
    GenServer.start_link(__MODULE__, :ok, opts ++ [name: __MODULE__])
  end

  def query_menu(query) do
    Logger.info("Querying menu with: #{inspect(query)}")

    try do
      GenServer.call(__MODULE__, {:query_menu, query}, @default_timeout)
    catch
      :exit, {:timeout, _} ->
        Logger.error("Menu query timed out after #{@default_timeout}ms", query: query)
        {:error, :timeout}

      error ->
        Logger.error("Unexpected error in menu query", error: error, query: query)
        {:error, :unknown}
    end
  end

  def ask_agents(query, agents) do
    Logger.info("Asking agents", query: query, agents: agents)

    try do
      GenServer.call(__MODULE__, {:ask_agents, query, agents}, @default_timeout)
    catch
      :exit, {:timeout, _} ->
        Logger.error("Agents query timed out after #{@default_timeout}ms",
          query: query,
          agents: agents
        )

        {:error, :timeout}

      error ->
        Logger.error("Unexpected error in agents query",
          error: error,
          query: query,
          agents: agents
        )

        {:error, :unknown}
    end
  end

  # Server Callbacks

  @impl true
  def init(:ok) do
    Logger.info("Initializing Jabba agent")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:query_menu, query}, from, state) do
    Logger.debug("Processing menu query", query: query, from: from)

    try do
      results = jabba_work(query)
      Logger.info("Menu query processed", results_length: String.length(results))
      {:reply, {:ok, results}, state}
    catch
      kind, error ->
        Logger.error("Error processing menu query",
          kind: kind,
          error: error,
          stacktrace: __STACKTRACE__
        )

        {:reply, {:error, :processing_failed}, state}
    end
  end

  defp jabba_work(query) do
    Logger.debug("Starting Jabba work", query: query)

    distance_result = Guido.check_distance(query)
    Logger.debug("Distance check result", result: distance_result)

    enriched_query = enrich_query_with_distance(distance_result, query)
    Logger.debug("Enriched query", query: enriched_query)

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

  defp enrich_query_with_distance(:bruh, query) do
    Logger.debug("No distance enrichment needed")
    query
  end

  defp enrich_query_with_distance({:ok, %{type: :direct_distance} = result}, query) do
    """
    #{query}
    Considera che la distanza tra #{result.source} e #{result.destination} è #{result.distance} unità.
    """
  end

  defp enrich_query_with_distance({:ok, %{type: :radius_search} = result}, query) do
    planets =
      result.planets
      |> Enum.map(fn %{planet: planet, distance: dist} ->
        "#{planet} (#{dist} unità)"
      end)
      |> Enum.join(", ")

    """
    #{query}
    I pianeti entro #{result.radius} unità da #{result.center} sono: #{planets}.
    """
  end

  defp enrich_query_with_distance(_, query), do: query

  defp parse_dishes(dishes) do
    Logger.debug("Parsing #{length(dishes)} dishes")

    result =
      Enum.reduce(
        dishes,
        [],
        fn dish, acc ->
          chef = QueryManager.get_by(project: @project_id, id: dish.data.link_chef)
          restaurant = QueryManager.get_by(project: @project_id, id: chef.data.link_restaurant)
          planet = QueryManager.get_by(project: @project_id, id: restaurant.data.link_planet)

          [
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

    Logger.debug("Finished parsing dishes", count: length(result))
    result
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
