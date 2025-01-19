defmodule Hackapizza.Rag.Retrieve do
  alias Arke.QueryManager
  alias Jason
  alias ArkePostgres.Repo
  import Ecto.Query

  @project_id :jabba_advisor

  def retrieve_data(query, cluster) when is_binary(cluster), do: retrieve_data(query, [cluster])
  def retrieve_data(query, cluster) do
    # Extract relevant entities from query
    entities = case extract_entities(query) do
      "" -> query
      filter -> filter
    end

    IO.inspect entities, label: "FILTER FOR RAG"

    # Calculate embedding using enhanced query
    query_embedding = calculate_embedding(entities)

    ids = Enum.reduce(cluster, [], fn c, acc ->
      contents = retrieve_relevant_documents(query_embedding, c, 20)
      contents ++ acc
    end)
    QueryManager.filter_by(project: @project_id, id__in: ids)
  end

  defp extract_entities(query) do
    case Hackapizza.WatsonX.extract_filter(query) do
      {:ok, data} ->
        Map.get(data, "positive")
        |> Enum.join(", ")

      {:error, reason} ->
        {:error, reason}
    end
  end
  defp retrieve_relevant_documents(query_embedding, cluster, limit) do

    query =
      from t in "embedding_data",
           order_by: fragment("embedding <=> ?", ^query_embedding),
           limit: ^limit,
           where: t.cluster == ^cluster,
           select: t.id

    Repo.all(query, prefix: @project_id)
  end

  defp calculate_embedding(content) do
    {:ok, response} = Hackapizza.WatsonX.generate_embeddings([content])
    response["results"] |> List.first() |> Map.get("embedding")
  end
end
