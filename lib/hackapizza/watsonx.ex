defmodule Hackapizza.WatsonX do
  @moduledoc """
  Module for interacting with IBM WatsonX API.
  """

  @default_model "meta-llama/llama-3-3-70b-instruct"
  @default_parameters %{
    "max_tokens" => 8000,
    "temperature" => 0
  }

  def generate(prompt, opts \\ []) do
    model = Keyword.get(opts, :model, @default_model)
    parameters = Keyword.get(opts, :parameters, @default_parameters)

    payload = %{
      "model_id" => model,
      "input" => prompt,
      "parameters" => parameters
    }

    with {:ok, token} <- get_iam_token(),
         {:ok, response} <- make_request(payload, token) do
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
           ]
         ) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} ->
        {:ok, token}

      error ->
        {:error, "Failed to get IAM token: #{inspect(error)}"}
    end
  end

  defp make_request(payload, token) do
    api_url = System.fetch_env!("WATSONX_API_URL")
    project_id = System.fetch_env!("WATSONX_PROJECT_ID")
    endpoint = "#{api_url}/ml/v1/text/generation?version=2023-05-29"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"},
      {"Accept", "application/json"}
    ]

    case Req.post(endpoint,
           json: Map.put(payload, "project_id", project_id),
           headers: headers
         ) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      error ->
        {:error, "WatsonX API request failed: #{inspect(error)}"}
    end
  end
end
