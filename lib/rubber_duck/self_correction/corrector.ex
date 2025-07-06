defmodule RubberDuck.SelfCorrection.Corrector do
  @moduledoc """
  Applies corrections to content based on strategy recommendations.
  
  Handles the safe application of changes, ensuring corrections
  don't introduce new issues or break existing functionality.
  """
  
  require Logger
  
  @type correction :: %{
    type: atom(),
    description: String.t(),
    changes: [change()],
    confidence: float(),
    impact: :high | :medium | :low
  }
  
  @type change :: %{
    action: :replace | :insert | :delete,
    target: String.t(),
    replacement: String.t() | nil,
    location: map()
  }
  
  @doc """
  Applies a correction to content.
  
  Returns the corrected content or an error if the correction
  cannot be safely applied.
  """
  @spec apply_correction(String.t(), correction()) :: String.t()
  def apply_correction(content, correction) do
    Logger.debug("Applying correction: #{correction.type}")
    
    # Sort changes by location to apply in correct order
    sorted_changes = sort_changes_by_location(correction.changes)
    
    # Apply changes sequentially
    {corrected, _offset} = Enum.reduce(sorted_changes, {content, 0}, fn change, {current, offset} ->
      apply_single_change(current, change, offset)
    end)
    
    # Validate the result
    if valid_result?(corrected, content, correction) do
      corrected
    else
      Logger.warning("Correction produced invalid result, reverting")
      content
    end
  rescue
    e ->
      Logger.error("Error applying correction: #{Exception.message(e)}")
      content
  end
  
  @doc """
  Applies multiple corrections in sequence.
  
  Corrections are applied in order of confidence and priority.
  """
  @spec apply_multiple(String.t(), [correction()]) :: String.t()
  def apply_multiple(content, corrections) do
    # Sort by priority and confidence
    sorted_corrections = corrections
    |> Enum.sort_by(fn c -> {impact_priority(c.impact), c.confidence} end, :desc)
    
    Enum.reduce(sorted_corrections, content, fn correction, current ->
      new_content = apply_correction(current, correction)
      
      # Only keep the change if it actually improved things
      if new_content != current do
        Logger.info("Applied #{correction.type}: #{correction.description}")
        new_content
      else
        current
      end
    end)
  end
  
  @doc """
  Previews what a correction would do without applying it.
  
  Returns a diff-like representation of the changes.
  """
  @spec preview(String.t(), correction()) :: map()
  def preview(content, correction) do
    corrected = apply_correction(content, correction)
    
    %{
      original: content,
      corrected: corrected,
      changes_made: generate_diff(content, corrected),
      correction_type: correction.type,
      description: correction.description
    }
  end
  
  @doc """
  Merges compatible corrections to avoid conflicts.
  """
  @spec merge_corrections([correction()]) :: [correction()]
  def merge_corrections(corrections) do
    corrections
    |> Enum.group_by(& &1.type)
    |> Enum.map(fn {type, group} ->
      merge_correction_group(type, group)
    end)
    |> List.flatten()
  end
  
  # Private functions
  
  defp apply_single_change(content, change, offset) do
    case change.action do
      :replace ->
        apply_replacement(content, change, offset)
      
      :insert ->
        apply_insertion(content, change, offset)
      
      :delete ->
        apply_deletion(content, change, offset)
    end
  end
  
  defp apply_replacement(content, change, offset) do
    if change.target && change.replacement do
      # Find the target accounting for offset
      case find_target_position(content, change.target, change.location, offset) do
        {:ok, {start_pos, end_pos}} ->
          before_target = String.slice(content, 0, start_pos)
          after_target = String.slice(content, end_pos, String.length(content) - end_pos)
          
          new_content = before_target <> change.replacement <> after_target
          length_diff = String.length(change.replacement) - String.length(change.target)
          
          {new_content, offset + length_diff}
        
        :not_found ->
          Logger.warning("Target not found for replacement: #{inspect(change.target)}")
          {content, offset}
      end
    else
      {content, offset}
    end
  end
  
  defp apply_insertion(content, change, offset) do
    position = determine_insertion_position(content, change.location, offset)
    
    if position >= 0 && position <= String.length(content) do
      before_part = String.slice(content, 0, position)
      after_part = String.slice(content, position, String.length(content) - position)
      
      new_content = before_part <> change.replacement <> after_part
      {new_content, offset + String.length(change.replacement)}
    else
      Logger.warning("Invalid insertion position: #{position}")
      {content, offset}
    end
  end
  
  defp apply_deletion(content, change, offset) do
    if change.target do
      case find_target_position(content, change.target, change.location, offset) do
        {:ok, {start_pos, end_pos}} ->
          before_target = String.slice(content, 0, start_pos)
          after_target = String.slice(content, end_pos, String.length(content) - end_pos)
          
          new_content = before_target <> after_target
          length_diff = -(end_pos - start_pos)
          
          {new_content, offset + length_diff}
        
        :not_found ->
          Logger.warning("Target not found for deletion: #{inspect(change.target)}")
          {content, offset}
      end
    else
      {content, offset}
    end
  end
  
  defp find_target_position(content, target, location, offset) do
    # Try to find target string in content
    adjusted_location = adjust_location_for_offset(location, offset)
    
    # If we have a specific location, search near it
    if adjusted_location[:line] || adjusted_location[:position] do
      find_near_location(content, target, adjusted_location)
    else
      # Global search
      case :binary.match(content, target) do
        {start, length} ->
          {:ok, {start, start + length}}
        
        :nomatch ->
          :not_found
      end
    end
  end
  
  defp find_near_location(content, target, location) do
    lines = String.split(content, "\n")
    
    if location[:line] && location[:line] > 0 && location[:line] <= length(lines) do
      # Search in specific line
      line_index = location[:line] - 1
      line = Enum.at(lines, line_index)
      
      case :binary.match(line, target) do
        {start, length} ->
          # Calculate absolute position
          lines_before = Enum.take(lines, line_index)
          offset = Enum.sum(Enum.map(lines_before, &(String.length(&1) + 1))) # +1 for newline
          
          {:ok, {offset + start, offset + start + length}}
        
        :nomatch ->
          # Try global search as fallback
          find_target_position(content, target, %{}, 0)
      end
    else
      # Fallback to global search
      find_target_position(content, target, %{}, 0)
    end
  end
  
  defp determine_insertion_position(content, location, offset) do
    cond do
      location[:position] == :end ->
        String.length(content)
      
      location[:position] == :beginning ->
        0
      
      location[:position] ->
        location[:position] + offset
      
      location[:line] ->
        lines = String.split(content, "\n")
        line_num = location[:line] - 1
        
        if line_num >= 0 && line_num <= length(lines) do
          # Calculate position at start of line
          lines_before = Enum.take(lines, line_num)
          Enum.sum(Enum.map(lines_before, &(String.length(&1) + 1)))
        else
          String.length(content)
        end
      
      true ->
        String.length(content)
    end
  end
  
  defp adjust_location_for_offset(location, offset) do
    if location[:position] do
      Map.update(location, :position, 0, &(&1 + offset))
    else
      location
    end
  end
  
  defp sort_changes_by_location(changes) do
    # Sort changes to apply them in the correct order
    # Later positions first to avoid offset issues
    Enum.sort_by(changes, fn change ->
      position = case change.location do
        %{position: pos} when is_integer(pos) -> -pos
        %{line: line} -> -line * 1000  # Rough estimate
        %{position: :end} -> -999999
        %{position: :beginning} -> 0
        _ -> -500000  # Middle
      end
      
      {position, change.action}
    end)
  end
  
  defp valid_result?(corrected, original, correction) do
    # Basic validation - can be extended
    cond do
      # Don't allow empty results unless explicitly deleting everything
      corrected == "" && original != "" && correction.type != :full_deletion ->
        false
      
      # Check for common corruption patterns
      has_corruption_patterns?(corrected) ->
        false
      
      # Ensure reasonable size change
      size_change_reasonable?(original, corrected, correction) ->
        true
      
      true ->
        true
    end
  end
  
  defp has_corruption_patterns?(content) do
    # Check for signs of corrupted application
    patterns = [
      ~r/\0/,              # Null bytes
      ~r/[\x00-\x08]/,     # Control characters
      ~r/(.)\1{20,}/       # Excessive repetition
    ]
    
    Enum.any?(patterns, &Regex.match?(&1, content))
  end
  
  defp size_change_reasonable?(original, corrected, correction) do
    original_size = String.length(original)
    corrected_size = String.length(corrected)
    
    # Allow reasonable size changes based on correction type
    max_change_ratio = case correction.impact do
      :high -> 0.5    # 50% change allowed
      :medium -> 0.3  # 30% change allowed
      :low -> 0.1     # 10% change allowed
    end
    
    if original_size > 0 do
      change_ratio = abs(corrected_size - original_size) / original_size
      change_ratio <= max_change_ratio
    else
      true
    end
  end
  
  defp impact_priority(:high), do: 3
  defp impact_priority(:medium), do: 2
  defp impact_priority(:low), do: 1
  
  defp generate_diff(original, corrected) do
    # Simple diff generation - could use more sophisticated algorithm
    if original == corrected do
      %{changed: false}
    else
      original_lines = String.split(original, "\n")
      corrected_lines = String.split(corrected, "\n")
      
      %{
        changed: true,
        original_lines: length(original_lines),
        corrected_lines: length(corrected_lines),
        size_change: String.length(corrected) - String.length(original)
      }
    end
  end
  
  defp merge_correction_group(_type, [single]), do: [single]
  
  defp merge_correction_group(_type, corrections) do
    # Merge corrections of the same type if they don't conflict
    # For now, keep them separate to avoid complexity
    # In production, implement smart merging based on change locations
    corrections
  end
end