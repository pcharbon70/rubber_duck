defmodule RubberDuck.Tool.Composition.Patterns.DataPipeline do
  @moduledoc """
  A common data processing pipeline pattern.
  
  This workflow pattern implements a typical data processing pipeline with:
  - Data fetching from various sources
  - Data validation and cleaning
  - Data transformation
  - Data storage
  - Error handling and monitoring
  """
  
  use RubberDuck.Workflows.Workflow
  
  
  workflow do
    # Step 1: Fetch data from source
    step :fetch_data do
      run RubberDuck.Tool.Composition.Step
      argument :source, input(:source)
      argument :params, input(:fetch_params)
      max_retries 3
    end
    
    # Step 2: Validate the fetched data
    step :validate_data do
      run RubberDuck.Tool.Composition.Step
      argument :data, result(:fetch_data)
      argument :schema, input(:validation_schema)
      max_retries 1
    end
    
    # Step 3: Clean the data (remove invalid records, fix formats)
    step :clean_data do
      run RubberDuck.Tool.Composition.Step
      argument :data, result(:validate_data)
      argument :rules, input(:cleaning_rules)
      max_retries 2
    end
    
    # Step 4: Transform the data to target format
    step :transform_data do
      run RubberDuck.Tool.Composition.Step
      argument :data, result(:clean_data)
      argument :target_format, input(:target_format)
      argument :transformations, input(:transformations)
      max_retries 2
    end
    
    # Step 5: Store the processed data
    step :store_data do
      run RubberDuck.Tool.Composition.Step
      argument :data, result(:transform_data)
      argument :destination, input(:destination)
      argument :storage_options, input(:storage_options)
      max_retries 3
      compensate RubberDuck.Tool.Composition.Step  # Compensate by rolling back storage
    end
    
    # Step 6: Generate processing report
    step :generate_report do
      run RubberDuck.Tool.Composition.Step
      argument :processed_data, result(:store_data)
      argument :metrics, %{
        source: result(:fetch_data),
        validated: result(:validate_data),
        cleaned: result(:clean_data),
        transformed: result(:transform_data),
        stored: result(:store_data)
      }
      max_retries 1
    end
    
    # Final step - the report will be the workflow result
  end
  
end
