defmodule Hackapizza.Solution do
  @moduledoc """
  Module for Solution.
  """

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

      # TODO: Call Jabba agent and get response
      {:ok, response} = {:ok, nil}

      # Format as CSV row
      [index + 1, Enum.map(response, & &1.id) |> Enum.join(",")]
      |> Enum.join(",")
    end)
    |> Stream.concat([""]) # Add empty line at end
    |> Enum.join("\n")
    |> write_results()
  end

  defp write_results(content) do
    timestamp = DateTime.utc_now() |> DateTime.to_string() |> String.replace(~r/[^\d]/, "")
    filename = "solution_run/results_#{timestamp}.csv"

    # Write header and content
    File.write!(filename, "row_id,result\n" <> content)

    {:ok, filename}
  end
end
