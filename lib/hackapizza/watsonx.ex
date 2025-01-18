defmodule Hackapizza.WatsonX do
  @moduledoc """
  Module for interacting with IBM WatsonX API.
  """

  @default_model "meta-llama/llama-3-3-70b-instruct"
  @embedding_models_default "intfloat/multilingual-e5-large"
  @default_timeout 60_000
  @default_parameters %{
    "max_tokens" => 8000,
    "temperature" => 0,
    "time_limit" => 120_000
  }

  def generate(prompt, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)
    parameters = Keyword.get(opts, :parameters, @default_parameters)

    payload =
      Map.merge(
        %{
          "model_id" => model,
          "input" => prompt
        },
        parameters
      )

    with {:ok, token} <- get_iam_token(),
         {:ok, response} <- generate_text(payload, token) do
      {:ok, response}
    end
  end

  def generate_embeddings(text, opts \\ []) do
    model = Keyword.get(opts, :embedding_models, @embedding_models_default)
    parameters = Keyword.get(opts, :parameters, @default_parameters)

    payload =
      Map.merge(
        %{
          "model_id" => model,
          "inputs" => text
        },
        parameters
      )

    with {:ok, token} <- get_iam_token(),
         {:ok, response} <- get_embeddings(payload, token) do
      {:ok, response}
    end
  end

  def generate_structured(prompt, schema, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)
    parameters = Keyword.get(opts, :parameters, @default_parameters)

    system_prompt = """
    You are a structured data extractor. Your response must be valid JSON that matches this schema:
    #{Jason.encode!(schema)}
    """

    messages = [
      %{role: "system", content: system_prompt},
      %{role: "user", content: prompt}
    ]

    payload =
      Map.merge(
        %{
          "model_id" => model,
          "messages" => messages
        },
        parameters
      )

    with {:ok, token} <- get_iam_token(),
         {:ok, response} <- chat(payload, token) do
      {:ok, response}
    end
  end

  defp get_iam_token do
    api_key = System.fetch_env!("WATSONX_API_KEY")

    case Req.post("https://iam.cloud.ibm.com/identity/token",
           form: [
             grant_type: "urn:ibm:params:oauth:grant-type:apikey",
             apikey: api_key
           ],
           headers: [
             {"Content-Type", "application/x-www-form-urlencoded"},
             {"Accept", "application/json"}
           ],
           receive_timeout: 120_000
         ) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      error ->
        {:error, "Failed to get IAM token: #{inspect(error)}"}
    end
  end

  defp generate_text(payload, token) do
    api_url = System.fetch_env!("WATSONX_API_URL")
    project_id = System.fetch_env!("WATSONX_PROJECT_ID")
    endpoint = "#{api_url}/ml/v1/text/generation?version=2023-10-25"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    case Req.post(endpoint,
           json: Map.put(payload, "project_id", project_id),
           headers: headers,
           receive_timeout: @default_timeout
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      error ->
        {:error, "WatsonX API request failed: #{inspect(error)}"}
    end
  end

  defp chat(payload, token) do
    api_url = System.fetch_env!("WATSONX_API_URL")
    project_id = System.fetch_env!("WATSONX_PROJECT_ID")
    endpoint = "#{api_url}/ml/v1/text/chat?version=2023-10-25"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    case Req.post(endpoint,
           json: Map.put(payload, "project_id", project_id),
           headers: headers,
           receive_timeout: @default_timeout
         ) do
      {:ok, %{status: 200, body: body}} ->
        content = get_in(body, ["choices", Access.at(0), "message", "content"])
        cleanup_chat_response(content)

      error ->
        {:error, "WatsonX API request failed: #{inspect(error)}"}
    end
  end

  defp get_embeddings(payload, token) do
    api_url = System.fetch_env!("WATSONX_API_URL")
    project_id = System.fetch_env!("WATSONX_PROJECT_ID")
    endpoint = "#{api_url}/ml/v1/text/embeddings?version=2023-10-25"
    case Req.post(endpoint,
           json: Map.put(payload, "project_id", project_id),
           headers: [
             {"Authorization", "Bearer #{token}"},
             {"Content-Type", "application/json"},
             {"Accept", "application/json"}
           ],
           receive_timeout: @default_timeout
         ) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response}

      error ->
        {:error, "Failed to generate embeddings: #{inspect(error)}"}
    end
  end

  defp cleanup_chat_response(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, parsed_json} ->
        {:ok, parsed_json}

      {:error, _} ->
        # Try to extract JSON from the content if it's wrapped in text
        case Regex.run(~r/\{.*\}/s, content) do
          [json_str] ->
            case Jason.decode(json_str) do
              {:ok, parsed_json} -> {:ok, parsed_json}
              error -> error
            end

          nil ->
            {:error, "Failed to parse JSON from response"}
        end
    end
  end

  defp cleanup_chat_response(_), do: {:error, "Invalid response format"}

end
