defmodule RubberDuck.MCP.Server.Tools.WorkflowExecutor do
  @moduledoc """
  Executes RubberDuck workflows through MCP.
  
  This tool allows AI assistants to trigger and monitor workflow executions,
  providing access to RubberDuck's powerful workflow orchestration capabilities.
  """
  
  use Hermes.Server.Component, type: :tool
  
  alias RubberDuck.Workflows.Engine
  alias RubberDuck.MCP.Server.{State, Streaming}
  alias Hermes.Server.Frame
  
  schema do
    field :workflow_name, {:required, :string}, 
      description: "Name of the workflow to execute"
    
    field :params, :map,
      description: "Parameters to pass to the workflow"
      
    field :async, :boolean,
      description: "Whether to execute asynchronously (returns immediately)",
      default: false
      
    field :timeout, :integer,
      description: "Execution timeout in milliseconds",
      default: 30_000
      
    field :stream_progress, :boolean,
      description: "Whether to stream progress updates",
      default: false
  end
  
  @impl true
  def execute(%{workflow_name: name, params: params, async: async, timeout: timeout, stream_progress: stream} = all_params, frame) do
    state = frame.assigns[:server_state] || %State{}
    
    # Record the request
    updated_state = State.record_request(state)
    frame = Frame.assign(frame, :server_state, updated_state)
    
    # Log the execution request (logging is handled at server level)
    
    if stream and not async do
      # Execute with streaming
      execute_with_streaming(name, params, timeout, frame)
    else
      # Execute normally
      case execute_workflow(name, params, async, timeout) do
        {:ok, result} ->
          # Workflow completed successfully
          {:ok, format_result(result), frame}
          
        {:error, :not_found} ->
          {:error, %{
            "code" => "workflow_not_found",
            "message" => "Workflow '#{name}' not found"
          }}
          
        {:error, reason} ->
          # Workflow failed
          {:error, %{
            "code" => "workflow_error", 
            "message" => "Workflow execution failed: #{inspect(reason)}"
          }}
      end
    end
  end
  
  # Private functions
  
  defp execute_workflow(name, params, async, timeout) do
    # TODO: Integrate with actual workflow engine
    # For now, return mock data
    if name == "test_workflow" do
      if async do
        {:ok, %{
          "execution_id" => "exec_#{System.unique_integer([:positive])}",
          "status" => "running",
          "message" => "Workflow started asynchronously"
        }}
      else
        # Simulate work
        Process.sleep(100)
        {:ok, %{
          "status" => "completed",
          "result" => %{
            "output" => "Workflow completed successfully",
            "metrics" => %{
              "duration_ms" => 100,
              "steps_executed" => 3
            }
          }
        }}
      end
    else
      {:error, :not_found}
    end
  end
  
  defp format_result(result) do
    result
  end
  
  defp execute_with_streaming(name, params, timeout, frame) do
    Streaming.with_stream(frame, "workflow:#{name}", fn frame, token ->
      # Simulate streaming workflow execution
      if name == "test_workflow" do
        # Send initial progress
        {:ok, frame} = Streaming.send_progress(frame, token, %{
          progress: 0.1,
          message: "Initializing workflow"
        })
        
        # Stream some output
        {:ok, frame} = Streaming.stream_chunk(frame, token, "Starting workflow execution...\n")
        Process.sleep(100)
        
        # More progress
        {:ok, frame} = Streaming.send_progress(frame, token, %{
          progress: 0.3,
          message: "Processing step 1"
        })
        {:ok, frame} = Streaming.stream_chunk(frame, token, "Step 1: Validating input parameters\n")
        Process.sleep(100)
        
        # Continue progress
        {:ok, frame} = Streaming.send_progress(frame, token, %{
          progress: 0.6,
          message: "Processing step 2"
        })
        {:ok, frame} = Streaming.stream_chunk(frame, token, "Step 2: Executing main logic\n")
        Process.sleep(100)
        
        # Final progress
        {:ok, frame} = Streaming.send_progress(frame, token, %{
          progress: 0.9,
          message: "Finalizing"
        })
        {:ok, frame} = Streaming.stream_chunk(frame, token, "Step 3: Generating output\n")
        Process.sleep(50)
        
        # Complete
        {:ok, frame} = Streaming.send_progress(frame, token, %{
          progress: 1.0,
          message: "Complete"
        })
        
        result = %{
          "status" => "completed",
          "result" => %{
            "output" => "Workflow completed successfully with streaming",
            "metrics" => %{
              "duration_ms" => 350,
              "steps_executed" => 3
            },
            "streamed" => true
          }
        }
        
        {:ok, result, frame}
      else
        {:error, %{
          "code" => "workflow_not_found",
          "message" => "Workflow '#{name}' not found"
        }}
      end
    end)
  end
end