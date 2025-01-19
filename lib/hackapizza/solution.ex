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
        IO.inspect("run request #{index}: #{question}")

        response =
          case Jabba.jabba_work(question) do
            %{"names" => []} ->
              %{"names" => res} = Jabba.generate_spicy_result(question)
              res

            %{"names" => response} ->
              response
          end

        # Format as CSV row
        [index + 1, response |> Enum.join(",")]
        |> Enum.join(",")
      end,
      max_concurrency: 10, # Limit to 10 simultaneous tasks
      timeout: :infinity   # Optional: Set timeout for each task
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
    File.write!("solution_run/results.csv", data)
  end

  defp write_results(content) do
    timestamp = DateTime.utc_now() |> DateTime.to_string() |> String.replace(~r/[^\d]/, "")
    filename = "solution_run/results_#{timestamp}.csv"

    # Write header and content
    File.write!(filename, "row_id,result\n" <> content)

    {:ok, filename}
  end
end
