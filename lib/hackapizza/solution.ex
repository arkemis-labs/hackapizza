defmodule Hackapizza.Solution do
  @moduledoc """
  Module for Solution.
  """
  alias Hackapizza.Agent.Jabba

  def run do
    # Create solution_run directory if it doesn't exist
    File.mkdir_p!("solution_run")

    # Read the CSV file
    "dataset/domande.csv"
    |> File.stream!()
    |> Stream.with_index()
    |> Stream.map(fn {line, index} ->
      # Clean the line from quotes and newlines
      question = line |> String.trim() |> String.trim("\"")
      {index, question}
    end)
    |> Task.async_stream(
      fn {index, question} ->
        response =
          case Jabba.query_menu(question) do
            {:ok, response} ->
              IO.inspect(response)
              response

            {:error, _reason} ->
              [""]
          end

        # Format as CSV row
        [index + 1, response |> Enum.join(",")]
        |> Enum.join(",")
      end,
      # Limit to 10 simultaneous tasks
      max_concurrency: 5,
      # Optional: Set timeout for each task
      timeout: :infinity
    )
    |> Stream.map(fn
      {:ok, result} -> result
      {:error, _reason} -> "Error"
    end)
    # Add empty line at end
    |> Stream.concat([""])
    |> Enum.join("\n")
    |> write_results()
  end

  defp write_results(data) do
    timestamp = DateTime.utc_now() |> DateTime.to_string() |> String.replace(~r/[^\d]/, "")
    filename = "solution_run/results_#{timestamp}.csv"
    File.write!(filename, data)
  end

  defp write_results(content) do
    timestamp = DateTime.utc_now() |> DateTime.to_string() |> String.replace(~r/[^\d]/, "")
    filename = "solution_run/results_#{timestamp}.csv"

    # Write header and content
    File.write!(filename, "row_id,result\n" <> content)

    {:ok, filename}
  end
end
