defmodule ChapterSplitter do
  @doc """
  Splits a text file into chapters based on "Capitolo N:" pattern.
  Returns a map where keys are chapter numbers and values are chapter contents.
  """
  def split_chapters(file_path) do
    file_path
    |> File.read!()
    |> split_by_chapters()
  end

  defp split_by_chapters(content) do
    # Regex to match "Capitolo N:" including the content until the next chapter
    regex = ~r/(?=Capitolo \d+:.*?)(.+?)(?=Capitolo \d+:|$)/s

    # Extract all chapters
    chapters =
      Regex.scan(regex, content, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.trim/1)

    # Extract chapter numbers
    numbers =
      Regex.scan(~r/Capitolo (\d+):/, content, capture: :all_but_first)
      |> List.flatten()
      |> Enum.map(&String.to_integer/1)

    # Combine chapter numbers with their content
    Enum.zip(numbers, chapters)
    |> Enum.into(%{})
  end

  @doc """
  Saves each chapter into separate files in the specified output directory.
  """
  def save_chapters(chapters, output_dir) do
    # Create output directory if it doesn't exist
    File.mkdir_p!(output_dir)

    Enum.each(chapters, fn {number, content} ->
      file_path = Path.join(output_dir, "capitolo_#{number}.txt")
      File.write!(file_path, content)
    end)
  end
end
