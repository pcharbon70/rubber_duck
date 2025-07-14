defmodule RubberDuck.Instructions do
  use Ash.Domain,
    otp_app: :rubber_duck

  resources do
    resource RubberDuck.Instructions.SecurityAudit
  end
end
