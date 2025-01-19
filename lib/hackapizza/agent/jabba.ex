defmodule Hackapizza.Agent.Jabba do
  use GenServer
  alias Hackapizza.Rag.Retrieve
  alias Hackapizza.Agent.Guido

  @clusters ["dish"]

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
    # Query the vector database for menu items
    results = Retrieve.retrieve_data(query, @clusters)
    {:reply, results, state}
  end

  @impl true
  def handle_call({:ask_agents, query, agents}, _from, state) do
    response = coordinate_agents(query, agents)
    {:reply, response, state}
  end

  # Private Functions

  defp coordinate_agents(query, agents) do
    Enum.reduce(agents, %{}, fn
      :guido, acc ->
        Map.put(acc, :guido, Guido.check_distance(query))

      _, acc ->
        # Handle other agents when they are implemented
        acc
    end)
  end
end
