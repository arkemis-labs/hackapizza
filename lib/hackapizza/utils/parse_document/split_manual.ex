defmodule SplitManual do
  def run do
    # Path to your input file
    input_file = "converted_dataset/misc/Manuale di Cucina.txt"
    # Output directory for the chapters
    output_dir = "converted_dataset/misc/chapters"

    # Split and save chapters
    chapters = ChapterSplitter.split_chapters(input_file)
    ChapterSplitter.save_chapters(chapters, output_dir)

    # Print summary
    IO.puts("Split #{map_size(chapters)} chapters into #{output_dir}")

    # Print chapter numbers found
    chapter_numbers = Map.keys(chapters) |> Enum.sort()
    IO.puts("Found chapters: #{Enum.join(chapter_numbers, ", ")}")
  end
end
