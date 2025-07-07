defmodule RubberDuck.Context do
  use Ash.Domain, otp_app: :rubber_duck

  @moduledoc """
  Domain for building and managing LLM contexts.

  This domain provides sophisticated context building mechanisms that combine
  different memory levels and code context, optimizing for token limits while
  maximizing relevance.
  """

  resources do
    # Context resources will be added as needed
  end
end
