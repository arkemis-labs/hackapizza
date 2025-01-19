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
      {:ok, %{"kind" => "sources", "sources" => sources}} ->
        IO.inspect(sources)

      {:ok, %{"kind" => "planets", "planets" => planets}} ->
        IO.inspect(planets)

      _ ->
        :error
    end
  end

  defp extract_planets_from_query(query) do
    schema =
      %{
        "kind" => "planets | sources",
        "planets" => ["string"],
        "sources" => %{
          "source" => "string",
          "destination" => "string"
        }
      }

    system_prompt =
      """
      Your only responsibility is to extract the source and destination planets from queries about distances between planets.
      The query must be asking about the distance between two planets, like:
      - "What's the distance from Tatooine to Asgard?"
      - "How far is Tatooine from Asgard?"
      - "Give me the 2 closest planets to Tatooine"
      - "Distance between Tatooine and Asgard"

      Extract the source and destination planets exactly as written.
      If the query is not specifically asking about distances between planets, return an error in the following form:
      {error: "The query is not about planet distances"}
      """

    WatsonX.generate_structured(query, schema, system_prompt: system_prompt)
  end
end
