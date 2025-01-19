defmodule Hackapizza.Agent.Guido do
  @moduledoc """
  Agent responsible for calculating and providing interplanetary distances.

  This agent handles requests for distance information between celestial bodies,
  helping coordinate interplanetary logistics and navigation.
  """

  use GenServer
  alias Hackapizza.WatsonX

  @distances_file "dataset/misc/Distanze.csv"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts ++ [name: __MODULE__])
  end

  def check_distance(query) do
    GenServer.call(__MODULE__, {:check_distance, query})
  end

  @impl true
  def init(:ok) do
    distances = load_distances()
    {:ok, %{distances: distances}}
  end

  @impl true
  def handle_call({:check_distance, query}, _from, %{distances: distances} = state) do
    case process_distance_query(query, distances) do
      {:ok, result} -> {:reply, result, state}
      :error -> {:reply, :bruh, state}
    end
  end

  defp load_distances do
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
    case extract_planets_from_query(query) do
      {:ok, %{"source" => source, "destination" => destination}} ->
        case get_in(distances, [source, destination]) do
          nil -> :error
          distance -> {:ok, %{source: source, destination: destination, distance: distance}}
        end

      _ ->
        :error
    end
  end

  defp extract_planets_from_query(query) do
    schema = %{
      "source" => "string",
      "destination" => "string"
    }

    WatsonX.generate_structured(query, schema)
  end
end
