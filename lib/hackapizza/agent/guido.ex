defmodule Hackapizza.Agent.Guido do
  @moduledoc """
  Agent responsible for calculating and providing interplanetary distances.

  This agent handles requests for distance information between celestial bodies,
  helping coordinate interplanetary logistics and navigation.
  """

  use GenServer
  require Logger
  alias Hackapizza.WatsonX

  @distances_file "dataset/misc/Distanze.csv"
  # 2 minutes timeout
  @default_timeout :timer.minutes(2)

  def start_link(opts \\ []) do
    Logger.info("Starting Guido agent")
    GenServer.start_link(__MODULE__, :ok, opts ++ [name: __MODULE__])
  end

  def check_distance(query) do
    Logger.info("Checking distance for query: #{inspect(query)}")

    try do
      GenServer.call(__MODULE__, {:check_distance, query}, @default_timeout)
    catch
      :exit, {:timeout, _} ->
        Logger.error("Distance check timed out after #{@default_timeout}ms", query: query)
        {:error, :timeout}

      error ->
        Logger.error("Unexpected error in distance check", error: error, query: query)
        {:error, :unknown}
    end
  end

  @impl true
  def init(:ok) do
    Logger.info("Initializing Guido agent")
    distances = load_distances()
    Logger.info("Loaded distances for #{map_size(distances)} planets")
    {:ok, %{distances: distances}}
  end

  @impl true
  def handle_call({:check_distance, query}, from, %{distances: distances} = state) do
    Logger.debug("Processing distance query", query: query, from: from)

    try do
      case process_distance_query(query, distances) do
        {:ok, result} ->
          Logger.info("Successfully processed distance query", result: result)
          {:reply, {:ok, result}, state}

        :error ->
          Logger.warn("Failed to process distance query", query: query)
          {:reply, :bruh, state}
      end
    catch
      kind, error ->
        Logger.error("Error processing distance query",
          kind: kind,
          error: error,
          stacktrace: __STACKTRACE__
        )

        {:reply, {:error, :processing_failed}, state}
    end
  end

  defp load_distances do
    Logger.debug("Loading distances from #{@distances_file}")

    @distances_file
    |> File.read!()
    |> String.split("\n")
    |> Enum.map(&String.split(&1, ","))
    |> parse_distances()
  end

  defp parse_distances([["/" | planets] | rows]) do
    planets = Enum.map(planets, &String.trim/1)

    rows
    |> Enum.reduce(%{}, fn [source | distances], acc ->
      source = String.trim(source)

      distances_map =
        Enum.zip(distances, planets)
        |> Map.new(fn {dist, planet} ->
          {planet, dist |> String.trim() |> String.to_integer()}
        end)

      Map.put(acc, source, distances_map)
    end)
  end

  defp process_distance_query(query, distances) do
    case extract_planets_from_query(query, distances) do
      {:ok, %{"center" => center, "radius" => radius, "operator" => operator}} ->
        get_planets(%{"center" => center, "radius" => radius, "operator" => operator}, distances)

      _ ->
        :error
    end
  end

  defp get_planets(%{"center" => center, "radius" => radius, "operator" => operator}, distances) do
    planets =
      distances
      |> Map.get(center)
      |> Enum.filter(fn {planet, distance} ->
        planet != center && apply_condition(operator, distance, radius)
      end)
      |> Enum.map(fn {planet, distance} ->
        %{planet: planet, distance: distance}
      end)

    {:ok, %{type: :radius_search, center: center, radius: radius, planets: planets}}
  end

  defp apply_condition("<=", distance, radius), do: distance <= radius
  defp apply_condition(">=", distance, radius), do: distance >= radius
  defp apply_condition("<", distance, radius), do: distance < radius
  defp apply_condition(">", distance, radius), do: distance > radius
  defp apply_condition("=", distance, radius), do: distance == radius

  defp extract_planets_from_query(query, distances) do
    Logger.debug("Extracting planets from query", query: query)

    schema =
      %{
        "center" => "string",
        "operator" => "<= | >= | < | > | =",
        "radius" => "number"
      }

    system_prompt =
      """
      Your only responsibility is to extract a condition from queries about interplanetary distances.
      The query can ask anything but you must be able to extract a condition about distances between planets, like:

      <QUESTION>"Quali sono i piatti disponibili nei ristoranti entro 126 anni luce da Cybertron, quest'ultimo incluso, che non includono Funghi dell'Etere?"</QUESTION>
      <ANSWER>{"center": "Cybertron", "radius": 126, "operator": "<="}</ANSWER>

      <QUESTION>"Quali piatti possiamo gustare in un ristorante entro 83 anni luce da Cybertron, quest'ultimo incluso, evitando rigorosamente quelli cucinati con Farina di Nettuno?"</QUESTION>
      <ANSWER>{"center": "Cybertron", "radius": 83, "operator": "<="}</ANSWER>

      Available planets are #{distances |> Map.keys() |> Enum.join(", ")}

      Anything else is not a valid query and you must return an error.
      """

    result = WatsonX.generate_structured(query, schema, system_prompt: system_prompt)
    Logger.debug("Extracted planets result", result: result)
    result
  end
end
