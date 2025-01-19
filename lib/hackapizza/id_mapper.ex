defmodule Hackapizza.IdMapper do
  @moduledoc """
  Module for mapping dish names to IDs using the dish_mapping.json file.
  """

  def map_last_results_to_ids do
    # Get the latest results file
    last_file =
      "solution_run"
      |> File.ls!()
      |> Enum.filter(&String.starts_with?(&1, "results_"))
      |> Enum.sort()
      |> List.last()

    # Create solution_with_id directory if it doesn't exist
    File.mkdir_p!("solution_with_id")

    # Read the dish mapping
    dish_mapping =
      "dataset/misc/dish_mapping.json"
      |> File.read!()
      |> Jason.decode!()

    # Process the file
    content =
      "solution_run/#{last_file}"
      |> File.stream!()
      |> Stream.with_index()
      |> Stream.map(fn {line, index} ->
        if index == 0 do
          # Return header as is
          line
        else
          # Process data line
          [row_id | names] = String.trim(line) |> String.split(",")

          # Map names to IDs
          ids = names |> Enum.map(&Map.get(dish_mapping, &1, rand()))

          # Format as CSV row
          [row_id | ids] |> Enum.join(",")
        end
      end)
      |> Enum.join("\n")

    # Write to new file with _with_id suffix
    new_filename = String.replace(last_file, ".csv", "_with_id.csv")
    File.write!("solution_with_id/#{new_filename}", content)

    {:ok, "solution_with_id/#{new_filename}"}
  end

  defp rand, do: :rand.uniform(200)
end
