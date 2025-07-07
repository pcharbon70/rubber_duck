defmodule RubberDuck.SelfCorrection.CorrectorTest do
  use ExUnit.Case, async: true

  alias RubberDuck.SelfCorrection.Corrector

  describe "apply_correction/2" do
    test "applies simple replacement correction" do
      content = "Hello wrold!"

      correction = %{
        type: :spelling,
        description: "Fix spelling error",
        changes: [
          %{
            action: :replace,
            target: "wrold",
            replacement: "world",
            location: %{}
          }
        ],
        confidence: 0.9,
        impact: :low
      }

      result = Corrector.apply_correction(content, correction)
      assert result == "Hello world!"
    end

    test "applies insertion correction" do
      content = "def hello do\n  'world'\nend"

      correction = %{
        type: :documentation,
        description: "Add documentation",
        changes: [
          %{
            action: :insert,
            target: "",
            replacement: "  @doc \"Says hello\"\n",
            location: %{line: 1}
          }
        ],
        confidence: 0.8,
        impact: :medium
      }

      result = Corrector.apply_correction(content, correction)
      assert result =~ "@doc"
    end

    test "applies deletion correction" do
      content = "Hello  world!"

      correction = %{
        type: :formatting,
        description: "Remove extra space",
        changes: [
          %{
            action: :delete,
            target: "  ",
            replacement: " ",
            location: %{}
          }
        ],
        confidence: 0.95,
        impact: :low
      }

      result = Corrector.apply_correction(content, correction)
      assert result == "Hello world!"
    end

    test "handles multiple changes in correct order" do
      content = "abc def ghi"

      correction = %{
        type: :multi_fix,
        description: "Multiple fixes",
        changes: [
          %{action: :replace, target: "abc", replacement: "123", location: %{position: 0}},
          %{action: :replace, target: "def", replacement: "456", location: %{position: 4}},
          %{action: :replace, target: "ghi", replacement: "789", location: %{position: 8}}
        ],
        confidence: 0.8,
        impact: :medium
      }

      result = Corrector.apply_correction(content, correction)
      assert result == "123 456 789"
    end

    test "validates result and reverts on corruption" do
      content = "Valid content"

      correction = %{
        type: :dangerous,
        description: "Dangerous change",
        changes: [
          %{
            action: :replace,
            target: "Valid content",
            # Would empty the content
            replacement: "",
            location: %{}
          }
        ],
        confidence: 0.5,
        impact: :high
      }

      result = Corrector.apply_correction(content, correction)
      # Should revert
      assert result == content
    end

    test "handles errors gracefully" do
      content = "Test content"

      correction = %{
        type: :error_prone,
        description: "Error prone change",
        changes: [
          %{
            action: :invalid_action,
            target: "Test",
            replacement: "Best",
            location: %{}
          }
        ],
        confidence: 0.7,
        impact: :medium
      }

      result = Corrector.apply_correction(content, correction)
      # Should return original on error
      assert result == content
    end
  end

  describe "apply_multiple/2" do
    test "applies multiple corrections in priority order" do
      content = "helo wrold!"

      corrections = [
        %{
          type: :spelling,
          description: "Fix 'wrold'",
          changes: [%{action: :replace, target: "wrold", replacement: "world", location: %{}}],
          confidence: 0.9,
          impact: :medium
        },
        %{
          type: :spelling,
          description: "Fix 'helo'",
          changes: [%{action: :replace, target: "helo", replacement: "hello", location: %{}}],
          confidence: 0.95,
          impact: :high
        }
      ]

      result = Corrector.apply_multiple(content, corrections)
      assert result == "hello world!"
    end

    test "skips corrections that don't improve content" do
      content = "Good content"

      corrections = [
        %{
          type: :no_op,
          description: "No change",
          changes: [],
          confidence: 0.5,
          impact: :low
        }
      ]

      result = Corrector.apply_multiple(content, corrections)
      assert result == content
    end
  end

  describe "preview/2" do
    test "previews correction without applying" do
      content = "Hello wrold!"

      correction = %{
        type: :spelling,
        description: "Fix spelling",
        changes: [%{action: :replace, target: "wrold", replacement: "world", location: %{}}],
        confidence: 0.9,
        impact: :low
      }

      preview = Corrector.preview(content, correction)

      assert preview.original == content
      assert preview.corrected == "Hello world!"
      assert preview.correction_type == :spelling
      assert preview.description == "Fix spelling"
      assert Map.has_key?(preview, :changes_made)
    end
  end

  describe "merge_corrections/1" do
    test "groups corrections by type" do
      corrections = [
        %{type: :spelling, changes: [], confidence: 0.9, impact: :low},
        %{type: :spelling, changes: [], confidence: 0.8, impact: :low},
        %{type: :formatting, changes: [], confidence: 0.7, impact: :medium}
      ]

      merged = Corrector.merge_corrections(corrections)

      # For now, merge_corrections keeps them separate
      assert length(merged) == 3
    end
  end

  describe "edge cases" do
    test "handles empty content" do
      content = ""

      correction = %{
        type: :add_content,
        description: "Add content",
        changes: [%{action: :insert, target: "", replacement: "Hello", location: %{position: 0}}],
        confidence: 0.8,
        impact: :high
      }

      result = Corrector.apply_correction(content, correction)
      assert result == "Hello"
    end

    test "handles corrections at end of content" do
      content = "Hello"

      correction = %{
        type: :punctuation,
        description: "Add punctuation",
        changes: [%{action: :insert, target: "", replacement: "!", location: %{position: :end}}],
        confidence: 0.9,
        impact: :low
      }

      result = Corrector.apply_correction(content, correction)
      assert result == "Hello!"
    end

    test "handles line-based locations" do
      content = "Line 1\nLine 2\nLine 3"

      correction = %{
        type: :insert_line,
        description: "Insert between lines",
        changes: [%{action: :insert, target: "", replacement: "New Line", location: %{line: 2}}],
        confidence: 0.8,
        impact: :medium
      }

      result = Corrector.apply_correction(content, correction)
      assert result =~ "New Line"
      lines = String.split(result, "\n")
      assert length(lines) == 4
    end
  end
end
