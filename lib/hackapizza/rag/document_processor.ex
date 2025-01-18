defmodule Hackapizza.Rag.DocumentProcessor do
  alias Arke.Boundary.ArkeManager
  alias Arke.StructManager
  alias Jason

  @project_id :jabba_advisor
  @excluded_parameters ["id", "inserted_at", "updated_at", "metadata", "arke_id"]

  defp split_menu(file_path) do
    file_path
    |> File.read!()
    |> String.trim()
    |> String.split("\nMenu\n")
  end

  defp extract_arke_parameters(arke_id) do
    ArkeManager.get(arke_id, @project_id)
    |> then(& &1.data.parameters)
    |> Enum.reduce(%{}, fn %{arke: parameter, id: id}, acc ->
      parsed_id = to_string(id)

      case Enum.member?(@excluded_parameters, parsed_id) do
        true -> acc
        false -> Map.put(acc, parsed_id, parse_link(parameter))
      end
    end)
  end

  defp parse_link(:link), do: "string"
  defp parse_link(arke_id), do: to_string(arke_id)

  @doc """
  Calls WatsonX to parse Planet, Restaurant Licences and Chef data.
  """
  defp parse_chef_data(chef_data) do
    planet_parameters = extract_arke_parameters(:planet)
    chef_parameters = extract_arke_parameters(:chef)
    restaurant_parameters = extract_arke_parameters(:restaurant)
    license_parameters = extract_arke_parameters(:license_level)

    schema = %{
      chef: chef_parameters,
      planet: planet_parameters,
      restaurant: restaurant_parameters,
      license_level: [license_parameters]
    }

    prompt =
      """
       Devi estrarre le seguenti informazioni dal <DOCUMENTO> che ti fornirò.
      <DOCUMENTO>: #{chef_data}
      """

    test = Hackapizza.WatsonX.generate_structured(prompt, schema)

    IO.inspect(test)
  end

  @doc """
  Calls WatsonX to parse Dishes data with timeout handling.
  """
  defp parse_dishes_data(dishes_data) do
    dishes_parameters = extract_arke_parameters(:dish)

    prompt =
      """
      Segui attentamente queste istruzioni. Devi estrarre le seguenti informazioni dal <DOCUMENTO> che ti fornirò.
      Crea un file JSON, ovvero una lista di dizionari, uno per ogni piatto nel documento:
      - *dish*: #{dishes_parameters}
      Se un valore non è presente, usa null come valore.

      <DOCUMENTO>: #{dishes_data}
      """
  end

  @doc """
  Process the menu document and creates Planet, Restaurant, Licences, Chef and Dish Arke units.
  It also creates the embedding vectors for each Dish.
  """
  def process_menu(file_path) do
    with [chef_data | dishes_data] <- split_menu(file_path),
         {:ok, chef_response} <- parse_chef_data(chef_data) do
      #  {:ok, dishes_response} <- parse_dishes_data(dishes_data) do
      {:ok, %{chef: chef_response}}
    else
      {:error, reason} ->
        {:error, "Failed to process menu: #{reason}"}

      error ->
        {:error, "Unexpected error: #{inspect(error)}"}
    end
  end
end
