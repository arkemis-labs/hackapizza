defmodule Hackapizza.Rag.Retrieve do
  alias Jason
  alias ArkePostgres.Repo
  import Ecto.Query

  @project_id :jabba_advisor

  def retrieve_data(query, cluster) when is_binary(cluster), do: retrieve_data(query, [cluster])
  def retrieve_data(query, cluster) do
    query_embedding = calculate_embedding(query)
    Enum.reduce(cluster, [], fn c, acc ->
      contents = retrieve_relevant_documents(query_embedding, c, 1)
      [contents | acc]
    end)
  end
  defp retrieve_relevant_documents(query_embedding, cluster, limit) do

    query =
      from t in "embedding_data",
           order_by: fragment("embedding <=> ?", ^query_embedding),
           limit: ^limit,
           where: t.cluster == ^cluster,
           select: %{
             id: t.id
           }

    Repo.all(query, prefix: @project_id)
  end

  defp calculate_embedding(content) do
    {:ok, response} = Hackapizza.WatsonX.generate_embeddings([content])
    response["results"] |> List.first() |> Map.get("embedding")
  end
end
