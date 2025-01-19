defmodule Hackapizza.Rag.Embedding do
  alias Arke.QueryManager
  alias Jason
  alias ArkePostgres.Repo

  @project_id :jabba_advisor

  def embed_dishes() do
    planet_list = QueryManager.filter_by(project: @project_id, arke_id: :planet)
    restaurant_list = QueryManager.filter_by(project: @project_id, arke_id: :restaurant)
    dishes = QueryManager.filter_by(project: @project_id, arke_id: :dish)
    chefs = QueryManager.filter_by(project: @project_id, arke_id: :chef)

    Enum.each(planet_list, fn planet ->
      planet_restaurants =
        Enum.filter(restaurant_list, fn restaurant ->
          restaurant.data.link_planet == to_string(planet.id)
        end)

      Enum.each(planet_restaurants, fn restaurant ->
        restaurant_dishes =
          Enum.filter(dishes, fn dish ->
            dish.data.link_restaurant == to_string(restaurant.id)
          end)

        restaurant_chef =
          Enum.find(chefs, fn chef ->
            chef.data.link_restaurant == to_string(restaurant.id)
          end)

        Enum.each(restaurant_dishes, fn dish ->
          generate_dish_embedding_string(planet, restaurant, restaurant_chef, dish)
          |> calculate_embedding()
          |> save_embeddings(to_string(dish.id))
        end)
      end)
    end)
  end

  defp generate_dish_embedding_string(planet, restaurant, chef, dish) do
    """
    Pianeta: #{planet.data.name}
    Ristorante: #{restaurant.data.name}
    Chef: #{chef.data.full_name}
    Licenze Chef: #{format_field(chef.data.license)}
    Piatto: #{dish.data.name}
    Ingredienti: #{format_field(dish.data.ingredients)}
    Tecniche di preparazione: #{format_field(dish.data.techniques)}
    #{if dish.data.cult && dish.data.cult != "", do: "Ordine associato: #{dish.data.cult}", else: ""}
    """
  end

  defp format_field(field) when is_list(field), do: Enum.reduce(field, "", fn f, acc -> "#{format_field(f)}, #{acc}" end)
  defp format_field(field) when is_map(field), do: Enum.map_join(field, " ", fn {k, v} -> "#{parse_key(k)} #{v}" end)
  defp format_field(field) when is_binary(field), do: field
  defp format_field(_), do: ""

  defp parse_key("level"), do: "Livello"
  defp parse_key("type"), do: "licenza"
  defp parse_key(other), do: other

  def save_embeddings(embedding, unit_id) do
    query = """
    INSERT INTO "jabba_advisor"."embedding_data"
    ("id", "cluster", "chunk_number", "embedding")
    VALUES ($1, 'dish', 1, $2)
    """
    params = [unit_id, embedding]
    Repo.query(query, params)
  end

  defp calculate_embedding(content) do
    {:ok, response} = Hackapizza.WatsonX.generate_embeddings([content])
    response["results"] |> List.first() |> Map.get("embedding")
  end
end
