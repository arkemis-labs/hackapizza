defmodule Hackapizza.Utils.MarkdownConverter do
  @moduledoc """
  Utility module for converting various file formats (PDF, DOCX, CSV, JSON, HTML) to Markdown.
  """

  @doc """
  Converts all supported files from 'dataset' directory to markdown files in 'dataset_md'.
  Returns a list of tuples with {:ok, filename} or {:error, filename, reason}.
  """
  def run do
    # Ensure output directory exists
    File.mkdir_p!("dataset_md")

    # Get all files from dataset directory
    Path.wildcard("dataset/**/*")
    |> Enum.filter(&File.regular?/1)
    |> Enum.map(&process_file/1)
  end

  defp process_file(file_path) do
    extension = Path.extname(file_path) |> String.downcase()
    file_name = Path.basename(file_path, extension)

    # Keep subfolder structure by getting relative path from dataset dir
    rel_path = Path.relative_to(file_path, "dataset")
    rel_dir = Path.dirname(rel_path)
    output_dir = Path.join("dataset_md", rel_dir)

    # Create output directory structure
    File.mkdir_p!(output_dir)

    output_path = Path.join(output_dir, "#{file_name}.txt")

    result =
      case extension do
        ".pdf" ->
          with {:ok, content} <- pdf_to_markdown(file_path) do
            File.write(output_path, content)
          end

        ".docx" ->
          with {:ok, content} <- docx_to_markdown(file_path) do
            File.write(output_path, content)
          end

        ".csv" ->
          with {:ok, content} <- File.read(file_path),
               {:ok, markdown} <- csv_to_markdown(content) do
            File.write(output_path, markdown)
          end

        ".json" ->
          with {:ok, content} <- File.read(file_path),
               {:ok, markdown} <- json_to_markdown(content) do
            File.write(output_path, markdown)
          end

        ".html" ->
          with {:ok, content} <- File.read(file_path),
               {:ok, markdown} <- html_to_markdown(content) do
            File.write(output_path, markdown)
          end

        _ ->
          {:error, "Unsupported file format: #{extension}"}
      end

    case result do
      :ok -> {:ok, file_path}
      {:error, reason} -> {:error, file_path, reason}
    end
  end

  @doc """
  Converts PDF content to Markdown.
  Uses Asciidoctor PDF converter for better PDF structure handling.
  """
  def pdf_to_markdown(pdf_path) do
    backend = get_backend(pdf_path)

    # First try using asciidoctor-pdf for direct conversion
    tmp_adoc = Path.join(System.tmp_dir(), "temp_#{:rand.uniform(1_000_000)}.adoc")

    try do
      case System.cmd("asciidoctor-pdf", ["--backend=text", "-o", tmp_adoc, pdf_path]) do
        {_, 0} ->
          # Read the converted content
          content = File.read!(tmp_adoc)

          # Process the content through our markdown converter
          formatted_text =
            content
            |> convert_asciidoc_to_markdown()
            |> process_document_structure()
            |> backend.process()

          {:ok, formatted_text}

        _ ->
          # Fallback to pdftotext if asciidoctor-pdf conversion fails
          fallback_pdf_conversion(pdf_path, backend)
      end
    rescue
      _ -> fallback_pdf_conversion(pdf_path, backend)
    after
      File.rm(tmp_adoc)
    end
  end

  defp fallback_pdf_conversion(pdf_path, backend) do
    case System.cmd("pdftotext", ["-layout", pdf_path, "-"]) do
      {output, 0} ->
        formatted_text =
          output
          |> String.split("\n")
          |> Enum.map(&format_line_as_markdown/1)
          |> process_document_structure()
          |> Enum.join("\n")
          |> backend.process()

        {:ok, formatted_text}

      {error, _} ->
        {:error, "Failed to convert PDF: #{error}"}
    end
  end

  defp format_line_as_markdown(line) do
    line = String.trim(line)

    cond do
      # Title detection (centered text, all caps)
      Regex.match?(~r/^\s*[A-Z][A-Z\s]+[A-Z]\s*$/, line) and String.length(line) <= 120 ->
        "# #{line}"

      # Subtitle or section header (mixed case, followed by newline)
      Regex.match?(~r/^[A-Z][a-z].*[.:]\s*$/, line) and String.length(line) <= 100 ->
        "## #{line}"

      # Subsection headers (numbered or bulleted)
      Regex.match?(~r/^(\d+\.|\*|\-)\s+[A-Z]/, line) ->
        "### #{line}"

      # List items
      Regex.match?(~r/^[\s]*[•\-\*]\s+/, line) ->
        "* #{String.replace(line, ~r/^[\s]*[•\-\*]\s+/, "")}"

      # Skip empty lines
      line == "" ->
        ""

      # Regular text lines
      true ->
        line
    end
  end

  defp process_document_structure(lines) do
    lines
    |> Enum.chunk_by(&(String.trim(&1) == ""))
    |> Enum.map(fn chunk ->
      if Enum.all?(chunk, &(String.trim(&1) == "")) do
        ""
      else
        Enum.join(chunk, "\n")
      end
    end)
  end

  defp convert_asciidoc_to_markdown(asciidoc_content) do
    asciidoc_content
    # Headers
    |> String.replace(~r/^(={1,6})\s+(.+?)$/m, fn _, level, content ->
      "#" <> String.duplicate("#", String.length(level) - 1) <> " " <> content
    end)
    # Formatting
    # Bold
    |> String.replace(~r/\*\*(.+?)\*\*/m, "**\\1**")
    # Also Bold
    |> String.replace(~r/__(.+?)__/m, "**\\1**")
    # Italic
    |> String.replace(~r/\*(.+?)\*/m, "*\\1*")
    # Also Italic
    |> String.replace(~r/_(.+?)_/m, "*\\1*")
    # Lists
    # Unordered lists
    |> String.replace(~r/^(\s*)[*\-]\s+/m, "\\1* ")
    # Ordered lists
    |> String.replace(~r/^(\s*)\d+\.\s+/m, "\\1* ")
    # Code blocks
    # Source blocks
    |> String.replace(~r/\[source,([^\]]+)\]\n----\n/m, "```\\1\n")
    # Code block end
    |> String.replace(~r/----\n/m, "```\n")
    # Tables
    # Table headers
    |> String.replace(~r/\|\s*===+\s*(\n|$)/, "\n")
    # Table header markers
    |> String.replace(~r/\[%header\]\n/, "")
    # Links
    # Internal links
    |> String.replace(~r/\[\[(.*?)\]\]/, "[\\1]")
    # External links
    |> String.replace(~r/link:(\S+)\[(.*?)\]/, "[\\2](\\1)")
    # Clean up
    # Normalize spacing
    |> String.replace(~r/\n{3,}/m, "\n\n")
    |> String.trim()
  end

  @doc """
  Converts DOCX content to Markdown.
  Requires pandoc system dependency.
  """
  def docx_to_markdown(docx_path) do
    case System.cmd("pandoc", ["-f", "docx", "-t", "markdown", docx_path]) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, "Failed to convert DOCX: #{error}"}
    end
  end

  @doc """
  Converts CSV content to Markdown table format.
  """
  def csv_to_markdown(csv_content) do
    try do
      rows =
        csv_content
        |> String.split("\n", trim: true)
        |> Enum.map(&String.split(&1, ",", trim: true))

      case rows do
        [headers | data] ->
          markdown = build_markdown_table(headers, data)
          {:ok, markdown}

        [] ->
          {:error, "Empty CSV content"}
      end
    rescue
      e -> {:error, "Failed to convert CSV: #{Exception.message(e)}"}
    end
  end

  @doc """
  Converts JSON content to Markdown.
  """
  def json_to_markdown(json_string) do
    try do
      case Jason.decode(json_string) do
        {:ok, decoded} ->
          markdown = format_json_as_markdown(decoded)
          {:ok, markdown}

        {:error, _} ->
          {:error, "Invalid JSON content"}
      end
    rescue
      e -> {:error, "Failed to convert JSON: #{Exception.message(e)}"}
    end
  end

  @doc """
  Converts HTML content to Markdown.
  Requires pandoc system dependency.
  """
  def html_to_markdown(html_content) do
    # Create a temporary file for the HTML content
    tmp_path = Path.join(System.tmp_dir(), "temp_#{:rand.uniform(1_000_000)}.html")

    try do
      File.write!(tmp_path, html_content)

      case System.cmd("pandoc", ["-f", "html", "-t", "markdown", tmp_path]) do
        {output, 0} -> {:ok, output}
        {error, _} -> {:error, "Failed to convert HTML: #{error}"}
      end
    rescue
      e -> {:error, "Failed to convert HTML: #{Exception.message(e)}"}
    after
      File.rm(tmp_path)
    end
  end

  # Private helper functions

  defp clean_and_format_text(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.join("\n\n")
  end

  defp build_markdown_table(headers, data) do
    # Create header row
    header_row = "| #{Enum.join(headers, " | ")} |"

    # Create separator row
    separator_row = "| #{Enum.map(headers, fn _ -> "---" end) |> Enum.join(" | ")} |"

    # Create data rows
    data_rows =
      Enum.map(data, fn row ->
        "| #{Enum.join(row, " | ")} |"
      end)

    # Combine all rows
    [header_row, separator_row | data_rows]
    |> Enum.join("\n")
  end

  defp format_json_as_markdown(data, level \\ 0) when is_map(data) do
    indent = String.duplicate("  ", level)

    data
    |> Enum.map(fn {key, value} ->
      formatted_value = format_json_value(value, level + 1)
      "#{indent}- **#{key}**: #{formatted_value}"
    end)
    |> Enum.join("\n")
  end

  defp format_json_value(value, level) when is_map(value) do
    "\n" <> format_json_as_markdown(value, level)
  end

  defp format_json_value(value, _level) when is_list(value) do
    items = Enum.map(value, fn item -> "  - #{inspect(item)}" end)
    "\n" <> Enum.join(items, "\n")
  end

  defp format_json_value(value, _level), do: inspect(value)

  @doc """
  Gets the backend for a given file by creating an InputDocument.
  """
  defp get_backend(fname) do
    # Create a struct similar to InputDocument
    input_doc = %{
      path_or_stream: fname,
      format: :asciidoc,
      backend: Hackapizza.Utils.MarkdownConverter.AsciiDocBackend
    }

    # Extract the backend
    input_doc.backend
  end

  defmodule AsciiDocBackend do
    def process(text) do
      # Add any additional processing specific to AsciiDoc format
      # For now, we'll just return the markdown-formatted text
      text
    end
  end
end
