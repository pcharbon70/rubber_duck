defmodule RubberDuck.Tool.Loader do
  @moduledoc """
  Loads all tools from the RubberDuck.Tools namespace on application startup.
  """
  
  use Task
  require Logger
  
  alias RubberDuck.Tool.Discovery
  
  def start_link(_) do
    Task.start_link(__MODULE__, :load_all_tools, [])
  end
  
  def load_all_tools do
    # Wait a bit for the registry to be fully initialized
    Process.sleep(100)
    
    Logger.info("Loading tools from RubberDuck.Tools namespace...")
    
    # Load all tools from the RubberDuck.Tools namespace
    Discovery.load_from_namespace(RubberDuck.Tools)
    
    # Get stats about loaded tools
    stats = Discovery.get_discovery_stats()
    
    Logger.info("""
    Tool loading complete:
    - Total tools: #{stats.total_tools}
    - By category: #{inspect(stats.by_category)}
    """)
  end
end