defmodule RubberDuck.Prompts.ResourcesTest do
  use RubberDuck.DataCase, async: true

  alias RubberDuck.Prompts
  alias RubberDuck.Accounts.User

  describe "Prompt resource" do
    setup do
      user = create_user()
      {:ok, user: user}
    end

    test "creates a prompt for a user", %{user: user} do
      assert {:ok, prompt} =
               Prompts.create_prompt(
                 %{
                   title: "Test Prompt",
                   description: "A test prompt",
                   content: "This is a {{variable}} prompt",
                   template_variables: %{"variable" => "string"},
                   is_active: true
                 },
                 actor: user
               )

      assert prompt.title == "Test Prompt"
      assert prompt.user_id == user.id
    end

    test "prevents access to other users' prompts", %{user: user} do
      other_user = create_user(username: "other_user", email: "other@example.com")

      {:ok, prompt} =
        Prompts.create_prompt(
          %{
            title: "Private Prompt",
            content: "Secret content"
          },
          actor: other_user
        )

      # User should not be able to read other user's prompt
      # Ash returns NotFound instead of Forbidden to avoid information leakage
      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Prompts.get_prompt(prompt.id, actor: user)
    end

    test "automatically creates version on update", %{user: user} do
      {:ok, prompt} =
        Prompts.create_prompt(
          %{
            title: "Versioned Prompt",
            content: "Original content"
          },
          actor: user
        )

      assert {:ok, _updated_prompt} =
               Prompts.update_prompt(prompt, %{content: "Updated content"}, actor: user)

      # Should have created a version
      assert {:ok, versions} = Prompts.list_prompt_versions(prompt.id, actor: user)
      assert length(versions) == 1
      assert hd(versions).content == "Original content"
    end

    test "searches within user's prompts only", %{user: user} do
      other_user = create_user(username: "other_user2", email: "other2@example.com")

      {:ok, _user_prompt} =
        Prompts.create_prompt(
          %{
            title: "My Searchable Prompt",
            content: "Unique content"
          },
          actor: user
        )

      {:ok, _other_prompt} =
        Prompts.create_prompt(
          %{
            title: "Other Searchable Prompt",
            content: "Unique content"
          },
          actor: other_user
        )

      # Search should only return user's prompt
      assert {:ok, results} = Prompts.search_prompts("Searchable", actor: user)
      assert length(results) == 1
      assert hd(results).title == "My Searchable Prompt"
    end
  end

  describe "Category resource" do
    setup do
      user = create_user()
      {:ok, user: user}
    end

    test "creates default 'General' category for new user", %{user: user} do
      # First, manually create the default General category
      {:ok, _category} =
        Prompts.create_category(
          %{
            name: "General",
            description: "Default category for prompts"
          },
          actor: user
        )

      assert {:ok, categories} = Prompts.list_categories(actor: user)
      assert length(categories) == 1
      assert hd(categories).name == "General"
      assert hd(categories).user_id == user.id
    end

    test "creates user-scoped categories", %{user: user} do
      assert {:ok, category} =
               Prompts.create_category(
                 %{
                   name: "Code Templates",
                   description: "Templates for code generation"
                 },
                 actor: user
               )

      assert category.user_id == user.id
      assert category.name == "Code Templates"
    end

    test "prevents access to other users' categories", %{user: user} do
      other_user = create_user(username: "category_user", email: "cat@example.com")

      {:ok, category} =
        Prompts.create_category(%{name: "Private Category"}, actor: other_user)

      # Ash returns NotFound instead of Forbidden to avoid information leakage
      assert {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}} =
               Prompts.get_category(category.id, actor: user)
    end
  end

  describe "Tag resource" do
    setup do
      user = create_user()
      {:ok, user: user}
    end

    test "creates user-scoped tags", %{user: user} do
      assert {:ok, tag} =
               Prompts.create_tag(
                 %{
                   name: "javascript",
                   color: "#f7df1e"
                 },
                 actor: user
               )

      assert tag.user_id == user.id
      assert tag.name == "javascript"
    end

    test "prevents duplicate tag names for same user", %{user: user} do
      {:ok, _tag} = Prompts.create_tag(%{name: "python"}, actor: user)

      # Should fail with unique constraint violation
      assert {:error, _error} =
               Prompts.create_tag(%{name: "python"}, actor: user)
    end

    test "allows same tag name for different users", %{user: user} do
      other_user = create_user(username: "tag_user", email: "tag@example.com")

      {:ok, _tag1} = Prompts.create_tag(%{name: "shared"}, actor: user)
      assert {:ok, _tag2} = Prompts.create_tag(%{name: "shared"}, actor: other_user)
    end
  end

  # Helper function to create test users
  defp create_user(attrs \\ %{}) do
    default_attrs = %{
      username: "test_user_#{System.unique_integer([:positive])}",
      email: "test#{System.unique_integer([:positive])}@example.com",
      password: "password123",
      password_confirmation: "password123"
    }

    attrs = Map.merge(default_attrs, Map.new(attrs))

    {:ok, user} = Ash.create(User, attrs, action: :register_with_password, authorize?: false)
    user
  end
end
