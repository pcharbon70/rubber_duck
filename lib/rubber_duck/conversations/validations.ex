defmodule RubberDuck.Conversations.Validations do
  @moduledoc """
  Custom validation functions for conversation resources.
  """

  @max_title_length 200
  @max_content_length 100_000
  @min_context_window 100
  @max_context_window 128_000

  def validate_title_length(changeset, _opts) do
    title = Ash.Changeset.get_attribute(changeset, :title)

    if title && String.length(title) > @max_title_length do
      Ash.Changeset.add_error(changeset, :title, "Title must be #{@max_title_length} characters or less")
    else
      changeset
    end
  end

  def validate_content_length(changeset, _opts) do
    content = Ash.Changeset.get_attribute(changeset, :content)

    if content && String.length(content) > @max_content_length do
      Ash.Changeset.add_error(changeset, :content, "Message content must be #{@max_content_length} characters or less")
    else
      changeset
    end
  end

  def validate_sequence_number(changeset, _opts) do
    sequence_number = Ash.Changeset.get_attribute(changeset, :sequence_number)

    if sequence_number && sequence_number < 1 do
      Ash.Changeset.add_error(changeset, :sequence_number, "Sequence number must be positive")
    else
      changeset
    end
  end

  def validate_context_window_size(changeset, _opts) do
    window_size = Ash.Changeset.get_attribute(changeset, :context_window_size)

    cond do
      window_size && window_size < @min_context_window ->
        Ash.Changeset.add_error(
          changeset,
          :context_window_size,
          "Context window must be at least #{@min_context_window}"
        )

      window_size && window_size > @max_context_window ->
        Ash.Changeset.add_error(changeset, :context_window_size, "Context window cannot exceed #{@max_context_window}")

      true ->
        changeset
    end
  end

  def validate_conversation_type(changeset, _opts) do
    conversation_type = Ash.Changeset.get_attribute(changeset, :conversation_type)
    valid_types = [:general, :coding, :debugging, :planning, :review]

    if conversation_type && conversation_type not in valid_types do
      Ash.Changeset.add_error(
        changeset,
        :conversation_type,
        "Invalid conversation type. Must be one of: #{Enum.join(valid_types, ", ")}"
      )
    else
      changeset
    end
  end
end
