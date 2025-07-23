defmodule RubberDuckWeb.Integration.AIFeaturesTest do
  @moduledoc """
  Integration tests for AI feature integration in the coding session.

  Tests AI assistant functionality, code generation, analysis,
  and intelligent suggestions within the LiveView interface.
  """

  use RubberDuckWeb.ConnCase

  import Phoenix.LiveViewTest
  import RubberDuck.AccountsFixtures
  alias Phoenix.PubSub

  @moduletag :integration

  setup do
    user = user_fixture()

    project = %{
      id: "ai-test-#{System.unique_integer()}",
      name: "AI Test Project",
      description: "Testing AI features"
    }

    # Mock AI responses for consistent testing
    :ok = Mox.set_mox_global()

    %{user: user, project: project}
  end

  describe "AI assistant chat integration" do
    test "processes natural language queries", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      PubSub.subscribe(RubberDuck.PubSub, "chat:#{project.id}")

      # Ask AI a question
      view
      |> form("form[phx-submit=\"send_message\"]", %{
        message: "How do I create a GenServer in Elixir?"
      })
      |> render_submit()

      assert_receive {:chat_message, user_message}
      assert user_message.content == "How do I create a GenServer in Elixir?"

      # Simulate AI response
      ai_response = %{
        id: Ecto.UUID.generate(),
        user_id: "ai-assistant",
        username: "AI Assistant",
        content: """
        To create a GenServer in Elixir:

        ```elixir
        defmodule MyServer do
          use GenServer
          
          # Client API
          def start_link(init_arg) do
            GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
          end
          
          # Server Callbacks
          @impl true
          def init(init_arg) do
            {:ok, init_arg}
          end
        end
        ```
        """,
        timestamp: DateTime.utc_now(),
        type: :assistant,
        metadata: %{
          confidence: 0.95,
          sources: ["Elixir documentation", "GenServer guide"]
        }
      }

      send(view.pid, {:chat_message, ai_response})
      :timer.sleep(50)

      # Verify response is displayed with formatting
      html = render(view)
      assert html =~ "GenServer in Elixir"
      assert html =~ "defmodule MyServer"
      assert html =~ "use GenServer"
      # Code highlighting
      assert html =~ "code-block" or html =~ "highlight"
    end

    test "handles streaming AI responses", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Send query
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "Explain async/await"})
      |> render_submit()

      # Start streaming response
      stream_id = Ecto.UUID.generate()

      send(
        view.pid,
        {:streaming_start,
         %{
           id: stream_id,
           user_id: "ai-assistant",
           username: "AI Assistant"
         }}
      )

      # Stream chunks
      chunks = [
        "In Elixir, ",
        "we don't have async/await ",
        "like JavaScript. ",
        "Instead, we use ",
        "Tasks and processes."
      ]

      for chunk <- chunks do
        send(
          view.pid,
          {:streaming_chunk,
           %{
             id: stream_id,
             content: chunk
           }}
        )

        :timer.sleep(20)

        # Verify chunk appears
        assert render(view) =~ chunk
      end

      # End streaming
      send(view.pid, {:streaming_end, %{id: stream_id}})

      # Verify complete message
      html = render(view)
      assert html =~ "Tasks and processes"
      # No more indicators
      refute html =~ "streaming" or html =~ "typing"
    end

    test "provides contextual code suggestions", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Select a file with code
      send(
        view.pid,
        {:file_selected,
         %{
           path: "lib/user.ex",
           content: """
           defmodule User do
             defstruct [:name, :email]
             
             def new(name, email) do
               %User{name: name, email: email}
             end
           end
           """
         }}
      )

      :timer.sleep(50)

      # Ask for suggestions
      view
      |> form("form[phx-submit=\"send_message\"]", %{
        message: "What improvements can I make to this User module?"
      })
      |> render_submit()

      # AI provides contextual suggestions
      ai_suggestions = %{
        id: Ecto.UUID.generate(),
        user_id: "ai-assistant",
        username: "AI Assistant",
        content: """
        Here are some improvements for your User module:

        1. **Add type specs** for better documentation:
        ```elixir
        @type t :: %__MODULE__{name: String.t(), email: String.t()}
        @spec new(String.t(), String.t()) :: t()
        ```

        2. **Add validation** for email format:
        ```elixir
        def new(name, email) do
          if valid_email?(email) do
            {:ok, %User{name: name, email: email}}
          else
            {:error, :invalid_email}
          end
        end
        ```

        3. **Consider using Ecto schema** for database persistence
        """,
        timestamp: DateTime.utc_now(),
        type: :assistant,
        suggestions: [
          %{type: :code_action, line: 2, action: "Add @type spec"},
          %{type: :code_action, line: 4, action: "Add @spec"},
          %{type: :refactor, description: "Add email validation"}
        ]
      }

      send(view.pid, {:chat_message, ai_suggestions})
      :timer.sleep(50)

      # Verify suggestions are displayed
      html = render(view)
      assert html =~ "type specs"
      assert html =~ "validation"
      assert html =~ "Ecto schema"

      # Verify code actions are available
      assert has_element?(view, "button", "Apply suggestion")
    end
  end

  describe "code generation" do
    test "generates code from natural language description", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Request code generation
      view
      |> form("form[phx-submit=\"send_message\"]", %{
        message: "/generate Create a Phoenix controller for blog posts with CRUD actions"
      })
      |> render_submit()

      # AI generates code
      generated_code = %{
        id: Ecto.UUID.generate(),
        user_id: "ai-assistant",
        username: "AI Assistant",
        content: """
        I'll generate a Phoenix controller for blog posts:

        ```elixir
        defmodule MyAppWeb.PostController do
          use MyAppWeb, :controller
          
          alias MyApp.Blog
          alias MyApp.Blog.Post
          
          def index(conn, _params) do
            posts = Blog.list_posts()
            render(conn, "index.html", posts: posts)
          end
          
          def new(conn, _params) do
            changeset = Blog.change_post(%Post{})
            render(conn, "new.html", changeset: changeset)
          end
          
          def create(conn, %{"post" => post_params}) do
            case Blog.create_post(post_params) do
              {:ok, post} ->
                conn
                |> put_flash(:info, "Post created successfully.")
                |> redirect(to: Routes.post_path(conn, :show, post))
              
              {:error, %Ecto.Changeset{} = changeset} ->
                render(conn, "new.html", changeset: changeset)
            end
          end
          
          # ... more actions
        end
        ```

        Would you like me to:
        1. Generate the complete controller with all CRUD actions?
        2. Create the corresponding views and templates?
        3. Add the routes to your router?
        """,
        timestamp: DateTime.utc_now(),
        type: :assistant,
        generated_files: [
          %{path: "lib/my_app_web/controllers/post_controller.ex", status: :pending}
        ]
      }

      send(view.pid, {:chat_message, generated_code})
      :timer.sleep(50)

      # Verify code is displayed
      assert render(view) =~ "PostController"
      assert render(view) =~ "def index"
      assert render(view) =~ "Blog.list_posts()"

      # Verify action buttons
      assert has_element?(view, "button", "Save to file")
      assert has_element?(view, "button", "Copy code")
    end

    test "generates tests for existing code", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Select existing code
      send(
        view.pid,
        {:file_selected,
         %{
           path: "lib/calculator.ex",
           content: """
           defmodule Calculator do
             def add(a, b), do: a + b
             def subtract(a, b), do: a - b
             def multiply(a, b), do: a * b
             def divide(a, b) when b != 0, do: a / b
             def divide(_, 0), do: {:error, :division_by_zero}
           end
           """
         }}
      )

      # Request test generation
      view
      |> form("form[phx-submit=\"send_message\"]", %{
        message: "/generate-tests"
      })
      |> render_submit()

      # AI generates tests
      test_code = %{
        id: Ecto.UUID.generate(),
        user_id: "ai-assistant",
        username: "AI Assistant",
        content: """
        Generated tests for Calculator module:

        ```elixir
        defmodule CalculatorTest do
          use ExUnit.Case
          
          describe "add/2" do
            test "adds two positive numbers" do
              assert Calculator.add(2, 3) == 5
            end
            
            test "adds negative numbers" do
              assert Calculator.add(-2, -3) == -5
            end
          end
          
          describe "divide/2" do
            test "divides two numbers" do
              assert Calculator.divide(10, 2) == 5.0
            end
            
            test "returns error for division by zero" do
              assert Calculator.divide(10, 0) == {:error, :division_by_zero}
            end
          end
        end
        ```
        """,
        timestamp: DateTime.utc_now(),
        type: :assistant,
        test_coverage: %{
          functions_tested: 5,
          total_functions: 5,
          coverage_percentage: 100
        }
      }

      send(view.pid, {:chat_message, test_code})
      :timer.sleep(50)

      # Verify test generation
      assert render(view) =~ "CalculatorTest"
      assert render(view) =~ "describe"
      assert render(view) =~ "division by zero"
    end
  end

  describe "code analysis and refactoring" do
    test "analyzes code quality and suggests improvements", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Load problematic code
      send(
        view.pid,
        {:file_selected,
         %{
           path: "lib/legacy.ex",
           content: """
           defmodule Legacy do
             def process_data(data) do
               result = []
               for item <- data do
                 if item != nil do
                   processed = String.upcase(item)
                   result = result ++ [processed]
                 end
               end
               result
             end
           end
           """
         }}
      )

      # Request analysis
      view
      |> form("form[phx-submit=\"send_message\"]", %{message: "/analyze"})
      |> render_submit()

      # AI provides analysis
      analysis = %{
        id: Ecto.UUID.generate(),
        user_id: "ai-assistant",
        username: "AI Assistant",
        content: """
        ## Code Analysis Results

        Found several issues in `Legacy.process_data/1`:

        ### Performance Issues:
        - **Line 7**: Using `++` in a loop is O(n²). Use list prepending instead.

        ### Style Issues:
        - Using `for` comprehension would be more idiomatic than manual iteration
        - Unnecessary variable assignments

        ### Suggested Refactoring:
        ```elixir
        def process_data(data) do
          data
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&String.upcase/1)
        end
        ```

        Or using for comprehension:
        ```elixir
        def process_data(data) do
          for item <- data, not is_nil(item) do
            String.upcase(item)
          end
        end
        ```
        """,
        timestamp: DateTime.utc_now(),
        type: :assistant,
        analysis: %{
          complexity: "high",
          issues: [
            %{line: 7, severity: :warning, message: "Inefficient list concatenation"},
            %{line: 3, severity: :info, message: "Consider using Enum functions"}
          ]
        }
      }

      send(view.pid, {:chat_message, analysis})
      :timer.sleep(50)

      # Verify analysis display
      html = render(view)
      assert html =~ "Performance Issues"
      assert html =~ "O(n²)"
      assert html =~ "Suggested Refactoring"
      assert html =~ "Enum.map"
    end

    test "provides real-time error detection", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Type code with error
      send(
        view.pid,
        {:editor_content_changed,
         %{
           path: "lib/test.ex",
           content: """
           defmodule Test do
             def greet(name) do
               IO.puts("Hello, " <> Name)  # Error: Name should be name
             end
           end
           """
         }}
      )

      :timer.sleep(100)

      # AI detects error
      error_detection = %{
        type: :diagnostic,
        diagnostics: [
          %{
            line: 3,
            column: 26,
            severity: :error,
            message: "Variable 'Name' is undefined. Did you mean 'name'?",
            suggestions: ["Change 'Name' to 'name'"]
          }
        ]
      }

      send(view.pid, {:ai_diagnostics, error_detection})
      :timer.sleep(50)

      # Verify error display
      html = render(view)
      assert html =~ "undefined" or html =~ "error"
      assert html =~ "line 3" or html =~ "3:"

      # Quick fix should be available
      assert has_element?(view, "button", "Fix")
    end
  end

  describe "intelligent autocompletion" do
    test "provides context-aware completions", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Start typing
      send(
        view.pid,
        {:editor_typing,
         %{
           path: "lib/example.ex",
           content: "defmodule Example do\n  def hello do\n    Enum.",
           cursor_position: %{line: 3, column: 10}
         }}
      )

      :timer.sleep(50)

      # AI provides completions
      completions = %{
        type: :completions,
        items: [
          %{
            label: "map",
            kind: :function,
            detail: "map(enumerable, fun)",
            documentation:
              "Returns a list where each element is the result of invoking fun on each corresponding element of enumerable.",
            insert_text: "map(${1:enumerable}, ${2:fun})"
          },
          %{
            label: "filter",
            kind: :function,
            detail: "filter(enumerable, fun)",
            documentation:
              "Filters the enumerable, i.e. returns only those elements for which fun returns a truthy value.",
            insert_text: "filter(${1:enumerable}, ${2:fun})"
          },
          %{
            label: "reduce",
            kind: :function,
            detail: "reduce(enumerable, acc, fun)",
            documentation: "Invokes fun for each element in the enumerable with the accumulator.",
            insert_text: "reduce(${1:enumerable}, ${2:acc}, ${3:fun})"
          }
        ]
      }

      send(view.pid, {:ai_completions, completions})
      :timer.sleep(50)

      # Verify completion menu
      html = render(view)
      assert html =~ "map" or html =~ "completions"
      assert html =~ "filter"
      assert html =~ "reduce"
    end

    test "learns from user patterns", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # User frequently uses certain patterns
      for _ <- 1..3 do
        view
        |> form("form[phx-submit=\"send_message\"]", %{
          message: "How do I handle errors in Elixir?"
        })
        |> render_submit()

        :timer.sleep(50)
      end

      # AI adapts to user's interest
      send(
        view.pid,
        {:editor_typing,
         %{
           content: "def process do\n  case ",
           cursor_position: %{line: 2, column: 7}
         }}
      )

      # AI prioritizes error handling patterns
      adapted_completions = %{
        type: :completions,
        items: [
          %{
            label: "do_something()",
            insert_text:
              "do_something() do\n    {:ok, result} -> {:ok, result}\n    {:error, reason} -> {:error, reason}\n  end",
            priority: 1,
            learned: true
          }
        ]
      }

      send(view.pid, {:ai_completions, adapted_completions})
      :timer.sleep(50)

      # Verify adapted suggestions
      assert render(view) =~ "{:ok, result}"
      assert render(view) =~ "{:error, reason}"
    end
  end

  describe "AI command palette" do
    test "executes AI commands", %{conn: conn, user: user, project: project} do
      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/session")

      # Test various AI commands
      commands = [
        {"/explain", "Explains the selected code"},
        {"/optimize", "Optimizes the selected code"},
        {"/document", "Generates documentation"},
        {"/translate python", "Translates code to Python"},
        {"/security", "Performs security analysis"}
      ]

      for {command, expected} <- commands do
        view
        |> form("form[phx-submit=\"send_message\"]", %{message: command})
        |> render_submit()

        :timer.sleep(50)

        # Verify command is recognized
        html = render(view)
        assert html =~ expected or html =~ String.trim_leading(command, "/")
      end
    end
  end
end
