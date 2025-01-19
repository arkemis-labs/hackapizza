defmodule Hackapizza.Agent.Guido do
  @moduledoc """
  Agent responsible for calculating and providing interplanetary distances.

  This agent handles requests for distance information between celestial bodies,
  helping coordinate interplanetary logistics and navigation.
  """

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts ++ [name: __MODULE__])
  end

  def check_distance(query) do
    GenServer.call(__MODULE__, {:check_distance, query})
  end

  @impl true
  def init(:ok) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:check_distance, _query}, _from, state) do
    # For now, always return false as requested
    {:reply, false, state}
  end
end
