defmodule RubberDuck.Instructions.FormatParser do
  @moduledoc """
  Parser for different instruction file formats.
  
  Supports multiple instruction file formats including:
  - Standard Markdown (.md)
  - Markdown with metadata (.mdc)
  - RubberDuck-specific format (RUBBERDUCK.md)
  - Cursor IDE rules (.cursorrules)
  
  Provides format detection, content extraction, and normalization
  to a consistent internal format.
  """

  alias RubberDuck.Instructions.TemplateProcessor

  @type format :: :markdown | :rubberduck_md | :cursorrules | :mdc
  @type parsed_content :: %{
    format: format(),
    metadata: map(),
    content: String.t(),
    sections: [section()],
    raw_content: String.t()
  }
  @type section :: %{
    title: String.t(),
    content: String.t(),
    level: integer(),
    type: atom()
  }

  @doc """
  Parses an instruction file based on its format.
  
  Automatically detects the format and extracts content accordingly.
  """
  @spec parse_file(String.t()) :: {:ok, parsed_content()} | {:error, term()}
  def parse_file(file_path) do
    with {:ok, content} <- File.read(file_path),
         {:ok, format} <- detect_format(file_path, content),
         {:ok, parsed} <- parse_content(content, format) do
      {:ok, Map.put(parsed, :raw_content, content)}
    end
  end

  @doc """
  Parses content with an explicitly specified format.
  """
  @spec parse_content(String.t(), format()) :: {:ok, parsed_content()} | {:error, term()}
  def parse_content(content, format) do
    case format do
      :markdown -> parse_markdown(content)
      :rubberduck_md -> parse_rubberduck_md(content)
      :cursorrules -> parse_cursorrules(content)
      :mdc -> parse_mdc(content)
      _ -> {:error, {:unsupported_format, format}}
    end
  end

  @doc """
  Detects the format of an instruction file.
  """
  @spec detect_format(String.t(), String.t()) :: {:ok, format()} | {:error, term()}
  def detect_format(file_path, content) do
    filename = Path.basename(file_path)
    extension = Path.extname(file_path)
    
    format = cond do
      String.ends_with?(filename, ".cursorrules") -> :cursorrules
      extension == ".mdc" -> :mdc
      filename in ["RUBBERDUCK.md", "rubber_duck.md", ".rubber_duck.md"] -> :rubberduck_md
      extension == ".md" -> :markdown
      has_cursorrules_markers?(content) -> :cursorrules
      has_rubberduck_markers?(content) -> :rubberduck_md
      true -> :markdown
    end
    
    {:ok, format}
  end

  @doc """
  Converts parsed content to a standardized format.
  """
  @spec normalize_content(parsed_content()) :: map()
  def normalize_content(parsed) do
    %{
      content: parsed.content,
      metadata: normalize_metadata(parsed.metadata, parsed.format),
      sections: normalize_sections(parsed.sections),
      format: parsed.format,
      instruction_type: determine_instruction_type(parsed),
      scope: determine_scope(parsed),
      tags: extract_tags(parsed)
    }
  end

  # Private functions

  defp parse_markdown(content) do
    case TemplateProcessor.extract_metadata(content) do
      {:ok, metadata, markdown_content} ->
        sections = extract_markdown_sections(markdown_content)
        
        {:ok, %{
          format: :markdown,
          metadata: metadata,
          content: markdown_content,
          sections: sections
        }}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_rubberduck_md(content) do
    # RUBBERDUCK.md format often has specific sections and conventions
    case TemplateProcessor.extract_metadata(content) do
      {:ok, metadata, markdown_content} ->
        sections = extract_rubberduck_sections(markdown_content)
        enhanced_metadata = enhance_rubberduck_metadata(metadata, sections)
        
        {:ok, %{
          format: :rubberduck_md,
          metadata: enhanced_metadata,
          content: markdown_content,
          sections: sections
        }}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_cursorrules(content) do
    # .cursorrules files typically use a specific format
    case parse_cursorrules_content(content) do
      {:ok, rules, metadata} ->
        # Convert rules to markdown-like sections
        sections = convert_rules_to_sections(rules)
        markdown_content = rules_to_markdown(rules)
        
        {:ok, %{
          format: :cursorrules,
          metadata: metadata,
          content: markdown_content,
          sections: sections
        }}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_mdc(content) do
    # .mdc files are markdown with enhanced metadata support
    case TemplateProcessor.extract_metadata(content) do
      {:ok, metadata, markdown_content} ->
        # Enhanced metadata processing for .mdc files
        enhanced_metadata = enhance_mdc_metadata(metadata)
        sections = extract_markdown_sections(markdown_content)
        
        {:ok, %{
          format: :mdc,
          metadata: enhanced_metadata,
          content: markdown_content,
          sections: sections
        }}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp has_cursorrules_markers?(content) do
    # Check for typical .cursorrules patterns
    cursorrules_patterns = [
      ~r/^# Cursor Rules/mi,
      ~r/^## Rules?$/mi,
      ~r/- You are an? .+ expert/i,
      ~r/- Always .+/i,
      ~r/- Never .+/i
    ]
    
    Enum.any?(cursorrules_patterns, &Regex.match?(&1, content))
  end

  defp has_rubberduck_markers?(content) do
    # Check for RubberDuck-specific patterns
    rubberduck_patterns = [
      ~r/## About me/mi,
      ~r/CRITICAL RULES/mi,
      ~r/ABSOLUTE RULE/mi,
      ~r/## Response Guidelines/mi,
      ~r/# RubberDuck/mi
    ]
    
    Enum.any?(rubberduck_patterns, &Regex.match?(&1, content))
  end

  defp extract_markdown_sections(content) do
    # Parse markdown headers and content
    lines = String.split(content, "\n")
    
    {sections, _} = 
      lines
      |> Enum.with_index()
      |> Enum.reduce({[], nil}, fn {line, index}, {sections, current_section} ->
        case parse_header(line) do
          {:header, level, title} ->
            # Start new section
            new_section = %{
              title: title,
              content: "",
              level: level,
              type: classify_section_type(title),
              start_line: index
            }
            
            # Finish previous section if exists
            updated_sections = case current_section do
              nil -> sections
              section -> [finish_section(section, index) | sections]
            end
            
            {updated_sections, new_section}
            
          :not_header ->
            # Add content to current section
            case current_section do
              nil -> {sections, nil}
              section ->
                updated_content = if section.content == "" do
                  line
                else
                  section.content <> "\n" <> line
                end
                updated_section = %{section | content: updated_content}
                {sections, updated_section}
            end
        end
      end)
    
    # Finish last section
    final_sections = case sections do
      [] -> []
      [current | rest] when is_map(current) -> [current | rest]
      _ -> sections
    end
    
    Enum.reverse(final_sections)
  end

  defp extract_rubberduck_sections(content) do
    # Enhanced section extraction for RUBBERDUCK.md format
    sections = extract_markdown_sections(content)
    
    # Enhance with RubberDuck-specific section types
    Enum.map(sections, fn section ->
      title_lower = String.downcase(section.title)
      enhanced_type = cond do
        String.contains?(title_lower, "critical rules") -> :critical_rules
        String.contains?(title_lower, "absolute rule") -> :absolute_rule
        String.contains?(title_lower, "about me") -> :context
        String.contains?(title_lower, "communication") -> :communication_rules
        String.contains?(title_lower, "response") -> :response_guidelines
        String.contains?(title_lower, "workflow") -> :workflow_rules
        String.contains?(title_lower, "hierarchy") -> :rule_hierarchy
        true -> section.type
      end
      
      %{section | type: enhanced_type}
    end)
  end

  defp parse_cursorrules_content(content) do
    # Parse .cursorrules format
    lines = String.split(content, "\n")
    
    rules = 
      lines
      |> Enum.filter(&(String.trim(&1) != ""))
      |> Enum.map(&parse_cursorrules_line/1)
      |> Enum.filter(&(&1 != nil))
    
    # Extract metadata from rules
    metadata = extract_cursorrules_metadata(rules)
    
    {:ok, rules, metadata}
  end

  defp parse_cursorrules_line(line) do
    trimmed = String.trim(line)
    
    cond do
      String.starts_with?(trimmed, "# ") ->
        {:header, 1, String.slice(trimmed, 2..-1//1)}
        
      String.starts_with?(trimmed, "## ") ->
        {:header, 2, String.slice(trimmed, 3..-1//1)}
        
      String.starts_with?(trimmed, "- ") ->
        {:rule, String.slice(trimmed, 2..-1//1)}
        
      String.starts_with?(trimmed, "* ") ->
        {:rule, String.slice(trimmed, 2..-1//1)}
        
      trimmed != "" ->
        {:text, trimmed}
        
      true ->
        nil
    end
  end

  defp extract_cursorrules_metadata(rules) do
    # Extract common metadata patterns from .cursorrules
    title = find_title_from_rules(rules)
    role = find_role_from_rules(rules)
    
    %{
      "title" => title,
      "role" => role,
      "type" => "auto",
      "format" => "cursorrules",
      "priority" => "normal"
    }
  end

  defp find_title_from_rules(rules) do
    case Enum.find(rules, fn rule -> match?({:header, 1, _}, rule) end) do
      {:header, 1, title} -> title
      _ -> "Cursor Rules"
    end
  end

  defp find_role_from_rules(rules) do
    # Look for "You are a/an X expert" patterns
    role_rule = Enum.find(rules, fn rule ->
      case rule do
        {:rule, text} -> String.match?(text, ~r/You are an? .+ expert/i)
        _ -> false
      end
    end)
    
    case role_rule do
      {:rule, text} ->
        case Regex.run(~r/You are an? (.+) expert/i, text) do
          [_, role] -> role
          _ -> "assistant"
        end
      _ -> "assistant"
    end
  end

  defp convert_rules_to_sections(rules) do
    {sections, current_section} = 
      Enum.reduce(rules, {[], nil}, fn rule, {sections, current} ->
        case rule do
          {:header, level, title} ->
            new_section = %{
              title: title,
              content: "",
              level: level,
              type: classify_section_type(title)
            }
            
            finished_sections = case current do
              nil -> sections
              section -> [section | sections]
            end
            
            {finished_sections, new_section}
            
          {:rule, text} ->
            case current do
              nil ->
                # Create default section
                default_section = %{
                  title: "Rules",
                  content: "- " <> text,
                  level: 1,
                  type: :rules
                }
                {sections, default_section}
                
              section ->
                updated_content = if section.content == "" do
                  "- " <> text
                else
                  section.content <> "\n- " <> text
                end
                {sections, %{section | content: updated_content}}
            end
            
          {:text, text} ->
            case current do
              nil -> {sections, nil}
              section ->
                updated_content = if section.content == "" do
                  text
                else
                  section.content <> "\n" <> text
                end
                {sections, %{section | content: updated_content}}
            end
        end
      end)
    
    # Add final section
    final_sections = case current_section do
      nil -> sections
      section -> [section | sections]
    end
    
    Enum.reverse(final_sections)
  end

  defp rules_to_markdown(rules) do
    rules
    |> Enum.map(fn rule ->
      case rule do
        {:header, 1, title} -> "# #{title}"
        {:header, 2, title} -> "## #{title}"
        {:header, level, title} -> String.duplicate("#", level) <> " #{title}"
        {:rule, text} -> "- #{text}"
        {:text, text} -> text
      end
    end)
    |> Enum.join("\n")
  end

  defp enhance_rubberduck_metadata(metadata, sections) do
    # Enhance metadata based on RUBBERDUCK.md content analysis
    critical_sections = Enum.filter(sections, &(&1.type == :critical_rules))
    
    enhanced = Map.merge(metadata, %{
      "format" => "rubberduck_md",
      "has_critical_rules" => length(critical_sections) > 0,
      "section_count" => length(sections)
    })
    
    # Determine priority based on content
    priority = cond do
      Enum.any?(sections, &(&1.type == :critical_rules)) -> "critical"
      Enum.any?(sections, &(&1.type == :absolute_rule)) -> "high"
      true -> Map.get(metadata, "priority", "normal")
    end
    
    Map.put(enhanced, "priority", priority)
  end

  defp enhance_mdc_metadata(metadata) do
    # Enhanced metadata processing for .mdc files
    Map.merge(metadata, %{
      "format" => "mdc",
      "enhanced_metadata" => true
    })
  end

  defp parse_header(line) do
    trimmed = String.trim(line)
    
    cond do
      String.starts_with?(trimmed, "# ") ->
        {:header, 1, String.slice(trimmed, 2..-1//1)}
        
      String.starts_with?(trimmed, "## ") ->
        {:header, 2, String.slice(trimmed, 3..-1//1)}
        
      String.starts_with?(trimmed, "### ") ->
        {:header, 3, String.slice(trimmed, 4..-1//1)}
        
      String.starts_with?(trimmed, "#### ") ->
        {:header, 4, String.slice(trimmed, 5..-1//1)}
        
      String.starts_with?(trimmed, "##### ") ->
        {:header, 5, String.slice(trimmed, 6..-1//1)}
        
      String.starts_with?(trimmed, "###### ") ->
        {:header, 6, String.slice(trimmed, 7..-1//1)}
        
      true ->
        :not_header
    end
  end

  defp classify_section_type(title) do
    title_lower = String.downcase(title)
    
    cond do
      title_lower =~ "rule" -> :rules
      title_lower =~ "instruction" -> :instructions
      title_lower =~ "guideline" -> :guidelines
      title_lower =~ "context" -> :context
      title_lower =~ "example" -> :examples
      title_lower =~ "format" -> :formatting
      title_lower =~ "workflow" -> :workflow
      title_lower =~ "communication" -> :communication
      title_lower =~ "response" -> :response
      true -> :general
    end
  end

  defp finish_section(section, end_line) do
    Map.put(section, :end_line, end_line - 1)
  end

  defp normalize_metadata(metadata, format) do
    # Normalize metadata across different formats
    base_metadata = %{
      "type" => "auto",
      "priority" => "normal",
      "scope" => "project",
      "format" => to_string(format)
    }
    
    Map.merge(base_metadata, metadata)
  end

  defp normalize_sections(sections) do
    # Normalize sections to consistent format
    Enum.map(sections, fn section ->
      %{
        title: section.title,
        content: String.trim(section.content),
        level: section.level,
        type: section.type,
        word_count: count_words(section.content)
      }
    end)
  end

  defp determine_instruction_type(parsed) do
    case Map.get(parsed.metadata, "type") do
      type when type in ["always", "auto", "agent", "manual"] -> String.to_atom(type)
      _ -> :auto
    end
  end

  defp determine_scope(parsed) do
    case Map.get(parsed.metadata, "scope") do
      scope when scope in ["project", "workspace", "global", "directory"] -> String.to_atom(scope)
      _ -> :project
    end
  end

  defp extract_tags(parsed) do
    # Extract tags from metadata and content
    metadata_tags = Map.get(parsed.metadata, "tags", [])
    content_tags = extract_content_tags(parsed.content)
    
    (metadata_tags ++ content_tags)
    |> Enum.uniq()
    |> Enum.take(10)  # Limit to 10 tags
  end

  defp extract_content_tags(content) do
    # Simple tag extraction from content
    content
    |> String.downcase()
    |> then(fn text ->
      cond do
        String.contains?(text, "security") -> ["security"]
        String.contains?(text, "performance") -> ["performance"]
        String.contains?(text, "testing") -> ["testing"]
        String.contains?(text, "documentation") -> ["documentation"]
        String.contains?(text, "elixir") -> ["elixir"]
        String.contains?(text, "phoenix") -> ["phoenix"]
        true -> []
      end
    end)
  end

  defp count_words(text) do
    text
    |> String.split(~r/\s+/)
    |> Enum.filter(&(String.trim(&1) != ""))
    |> length()
  end
end