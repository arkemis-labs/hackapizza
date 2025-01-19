defmodule Hackapizza.Rag.DocumentProcessor do
  alias Arke.Boundary.ArkeManager
  alias Arke.StructManager
  alias Arke.QueryManager
  require Logger

  @project_id :jabba_advisor
  @excluded_parameters ["id", "inserted_at", "updated_at", "metadata", "arke_id"]

  defp split_menu(file_path) do
    file_path
    |> File.read!()
    |> String.trim()
    |> String.split("\nMenu\n")
  end

  defp extract_arke_parameters(arke) do
    arke
    |> then(& &1.data.parameters)
    |> Enum.reduce(%{}, fn %{arke: parameter, id: id}, acc ->
      parsed_id = to_string(id)

      case Enum.member?(@excluded_parameters, parsed_id) or parameter == :link do
        true -> acc
        false -> Map.put(acc, parsed_id, to_string(parameter))
      end
    end)
  end

  @doc """
  Calls WatsonX to parse Planet, Restaurant Licences and Chef data.
  """
  defp parse_chef_data(chef_data) do
    planet = ArkeManager.get(:planet, @project_id)
    restaurant = ArkeManager.get(:restaurant, @project_id)
    chef = ArkeManager.get(:chef, @project_id)

    planet_parameters = extract_arke_parameters(planet)
    chef_parameters = extract_arke_parameters(chef)
    restaurant_parameters = extract_arke_parameters(restaurant)

    schema = %{
      # todo: add unit
      chef: Map.put(chef_parameters, "license", [%{level: "integer", type: "string"}]),
      planet: planet_parameters,
      restaurant: restaurant_parameters
    }

    prompt =
      """
       Devi estrarre le seguenti informazioni dal <DOCUMENTO> che ti fornirò.
      <DOCUMENTO>: #{chef_data}
      """

    case Hackapizza.WatsonX.generate_structured(prompt, schema) do
      {:ok, data} ->
        {:ok, planet} =
          QueryManager.create(@project_id, planet, data_as_klist(Map.get(data, "planet")))

        {:ok, restaurant} =
          QueryManager.create(
            @project_id,
            restaurant,
            data_as_klist(Map.put(Map.get(data, "restaurant"), :link_planet, planet.id))
          )

        {:ok, chef} =
          QueryManager.create(
            @project_id,
            chef,
            data_as_klist(Map.put(Map.get(data, "chef"), :link_restaurant, restaurant.id))
          )

        {:ok, %{planet: planet, restaurant: restaurant, chef: chef}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Calls WatsonX to parse Dishes data with timeout handling.
  """
  defp parse_dishes_data(dishes_data, chef_id) do
    dish = ArkeManager.get(:dish, @project_id)

    schema = %{
      dishes: [extract_arke_parameters(dish)]
    }

    prompt =
      """
       Devi estrarre le seguenti informazioni dal <DOCUMENTO> che ti fornirò.
       Il parametro *cult* rappresenta l'ordine alimentare che puo' essere:
        - 🪐 Ordine della Galassia di Andromeda
        - 🌱 Ordine dei Naturalisti
        - 🌈 Ordine degli Armonisti
        Possono essere rappresentati anche solo con il simbolo dell'ordine e possono trovarsi come legenda nel documento. Se non sono presenti, usa null come valore.
      <DOCUMENTO>: #{dishes_data}
      """

    case Hackapizza.WatsonX.generate_structured(prompt, schema) do
      {:ok, data} ->
        Enum.each(Map.get(data, "dishes"), fn d ->
          QueryManager.create(@project_id, dish, data_as_klist(Map.put(d, :link_chef, chef_id)))
        end)

        {:ok, data}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Process the menu document and creates Planet, Restaurant, Licences, Chef and Dish Arke units.
  It also creates the embedding vectors for each Dish.
  """
  def process_menu(file_path) do
    with [chef_data | dishes_data] <- split_menu(file_path),
         {:ok, %{chef: chef} = chef_response} <- parse_chef_data(chef_data),
         {:ok, dishes_response} <- parse_dishes_data(dishes_data, chef.id) do
      {:ok, %{chef: dishes_response}}
    else
      {:error, reason} ->
        {:error, "Failed to process menu: #{reason}"}

      error ->
        {:error, "Unexpected error: #{inspect(error)}"}
    end
  end

  defp data_as_klist(data) do
    Enum.map(data, fn {key, value} ->
      case is_atom(key) do
        true -> {key, value}
        false -> {String.to_existing_atom(key), value}
      end
    end)
  end

  @doc """
  Process all menu files in the dataset_md directory.
  Returns a tuple with successful and failed items.
  """
  def process_all_menus do
    dataset_path = "dataset_md/menu"

    files =
      File.ls!(dataset_path)
      |> Enum.filter(&String.ends_with?(&1, ".txt"))
      |> Enum.sort()
      |> Enum.map(&Path.join(dataset_path, &1))

    results =
      Enum.reduce(files, {[], []}, fn file_path, {successes, failures} ->
        Logger.info("Processing menu file: #{file_path}")

        case process_menu(file_path) do
          {:ok, result} ->
            Logger.info("Successfully processed #{file_path}")
            {[{file_path, result} | successes], failures}

          {:error, reason} ->
            Logger.error("Failed to process #{file_path}: #{reason}")
            {successes, [{file_path, reason} | failures]}
        end
      end)

    Logger.info(
      "Menu processing completed. Success: #{length(elem(results, 0))}, Failures: #{length(elem(results, 1))}"
    )

    results
  end
end
