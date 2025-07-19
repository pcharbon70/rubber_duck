defmodule RubberDuck.Tool.Composition.TransformerTest do
  use ExUnit.Case, async: true

  alias RubberDuck.Tool.Composition.Transformer

  describe "transform/2" do
    test "transforms data with type conversion" do
      assert {:ok, 123} = Transformer.transform("123", {:type, :integer})
      assert {:ok, "123"} = Transformer.transform(123, {:type, :string})
      assert {:ok, 123.0} = Transformer.transform(123, {:type, :float})
      assert {:ok, true} = Transformer.transform("true", {:type, :boolean})
    end

    test "transforms data with path extraction" do
      data = %{user: %{name: "John", age: 30}}

      assert {:ok, "John"} = Transformer.transform(data, {:extract, "user.name"})
      assert {:ok, 30} = Transformer.transform(data, {:extract, "user.age"})
    end

    test "transforms data with template application" do
      data = %{user: %{name: "John", age: 30}}
      template = "Hello {{user.name}}, you are {{user.age}} years old"

      assert {:ok, "Hello John, you are 30 years old"} = Transformer.transform(data, {:template, template})
    end

    test "transforms data with custom function" do
      custom_fun = fn data -> String.upcase(data) end

      assert {:ok, "HELLO"} = Transformer.transform("hello", {:custom, custom_fun})
    end

    test "transforms data with composition" do
      transformations = [
        {:type, :string},
        {:custom, fn s -> String.upcase(s) end}
      ]

      assert {:ok, "123"} = Transformer.transform(123, {:compose, transformations})
    end

    test "transforms data with map transformation" do
      data = ["hello", "world"]
      transformation = {:custom, fn s -> String.upcase(s) end}

      assert {:ok, ["HELLO", "WORLD"]} = Transformer.transform(data, {:map, transformation})
    end

    test "transforms data with filter" do
      data = [1, 2, 3, 4, 5]
      condition = {:greater_than, 3}

      assert {:ok, [4, 5]} = Transformer.transform(data, {:filter, condition})
    end

    test "handles unknown transformation type" do
      assert {:error, _} = Transformer.transform("data", {:unknown, :type})
    end
  end

  describe "convert_type/2" do
    test "converts to string" do
      assert {:ok, "123"} = Transformer.convert_type(123, :string)
      assert {:ok, "123.45"} = Transformer.convert_type(123.45, :string)
      assert {:ok, "true"} = Transformer.convert_type(true, :string)
    end

    test "converts to integer" do
      assert {:ok, 123} = Transformer.convert_type("123", :integer)
      assert {:ok, 123} = Transformer.convert_type(123.7, :integer)
      assert {:ok, 123} = Transformer.convert_type(123, :integer)
    end

    test "converts to float" do
      assert {:ok, 123.45} = Transformer.convert_type("123.45", :float)
      assert {:ok, 123.0} = Transformer.convert_type(123, :float)
      assert {:ok, 123.45} = Transformer.convert_type(123.45, :float)
    end

    test "converts to boolean" do
      assert {:ok, true} = Transformer.convert_type("true", :boolean)
      assert {:ok, false} = Transformer.convert_type("false", :boolean)
      assert {:ok, true} = Transformer.convert_type(1, :boolean)
      assert {:ok, false} = Transformer.convert_type(0, :boolean)
      assert {:ok, true} = Transformer.convert_type(true, :boolean)
    end

    test "converts to atom" do
      assert {:ok, :hello} = Transformer.convert_type("hello", :atom)
      assert {:ok, :hello} = Transformer.convert_type(:hello, :atom)
    end

    test "converts to list" do
      assert {:ok, [1, 2, 3]} = Transformer.convert_type([1, 2, 3], :list)
      assert {:ok, result} = Transformer.convert_type(%{a: 1, b: 2}, :list)
      assert Enum.sort(result) == Enum.sort(a: 1, b: 2)
    end

    test "converts to map" do
      assert {:ok, %{a: 1, b: 2}} = Transformer.convert_type(%{a: 1, b: 2}, :map)
      assert {:ok, %{a: 1, b: 2}} = Transformer.convert_type([a: 1, b: 2], :map)
    end

    test "converts to JSON" do
      assert {:ok, "{\"a\":1}"} = Transformer.convert_type(%{a: 1}, :json)
    end

    test "converts from JSON" do
      assert {:ok, %{"a" => 1}} = Transformer.convert_type("{\"a\":1}", :from_json)
    end

    test "handles conversion errors" do
      assert {:error, _} = Transformer.convert_type("not_a_number", :integer)
      assert {:error, _} = Transformer.convert_type("not_a_float", :float)
    end
  end

  describe "extract_path/2" do
    test "extracts simple paths" do
      data = %{user: %{name: "John", age: 30}}

      assert {:ok, "John"} = Transformer.extract_path(data, "user.name")
      assert {:ok, 30} = Transformer.extract_path(data, "user.age")
    end

    test "extracts array indices" do
      data = %{users: [%{name: "John"}, %{name: "Jane"}]}

      assert {:ok, %{name: "John"}} = Transformer.extract_path(data, "users[0]")
      assert {:ok, "John"} = Transformer.extract_path(data, "users[0].name")
    end

    test "extracts with wildcards" do
      data = %{users: [%{name: "John"}, %{name: "Jane"}]}

      assert {:ok, [%{name: "John"}, %{name: "Jane"}]} = Transformer.extract_path(data, "users[*]")
    end

    test "handles non-existent paths" do
      data = %{user: %{name: "John"}}

      assert {:ok, nil} = Transformer.extract_path(data, "user.nonexistent")
    end

    test "handles path extraction errors" do
      assert {:error, _} = Transformer.extract_path("not_a_map", "user.name")
    end
  end

  describe "apply_template/2" do
    test "applies simple templates" do
      data = %{name: "John", age: 30}
      template = "Hello {{name}}, you are {{age}} years old"

      assert {:ok, "Hello John, you are 30 years old"} = Transformer.apply_template(data, template)
    end

    test "applies nested path templates" do
      data = %{user: %{name: "John", profile: %{title: "Developer"}}}
      template = "{{user.name}} is a {{user.profile.title}}"

      assert {:ok, "John is a Developer"} = Transformer.apply_template(data, template)
    end

    test "handles missing template variables" do
      data = %{name: "John"}
      template = "Hello {{name}}, you are {{age}} years old"

      assert {:ok, "Hello John, you are  years old"} = Transformer.apply_template(data, template)
    end

    test "handles template application errors" do
      assert {:error, _} = Transformer.apply_template("not_a_map", "{{name}}")
    end
  end

  describe "apply_custom_function/2" do
    test "applies custom function successfully" do
      custom_fun = fn data -> String.upcase(data) end

      assert {:ok, "HELLO"} = Transformer.apply_custom_function("hello", custom_fun)
    end

    test "handles custom function errors" do
      failing_fun = fn _data -> raise "Custom function error" end

      assert {:error, _} = Transformer.apply_custom_function("data", failing_fun)
    end
  end

  describe "compose_transformations/2" do
    test "composes multiple transformations successfully" do
      transformations = [
        {:type, :string},
        {:custom, fn s -> String.upcase(s) end},
        {:custom, fn s -> s <> "!" end}
      ]

      assert {:ok, "123!"} = Transformer.compose_transformations(123, transformations)
    end

    test "stops composition on first error" do
      transformations = [
        {:type, :string},
        # This will fail
        {:type, :integer},
        {:custom, fn s -> String.upcase(s) end}
      ]

      assert {:error, _} = Transformer.compose_transformations(123, transformations)
    end
  end

  describe "map_transformation/2" do
    test "maps transformation over list successfully" do
      data = [1, 2, 3]
      transformation = {:type, :string}

      assert {:ok, ["1", "2", "3"]} = Transformer.map_transformation(data, transformation)
    end

    test "handles transformation errors in map" do
      data = [1, "not_a_number", 3]
      transformation = {:type, :integer}

      assert {:error, _} = Transformer.map_transformation(data, transformation)
    end

    test "requires list input for map transformation" do
      assert {:error, _} = Transformer.map_transformation("not_a_list", {:type, :string})
    end
  end

  describe "filter_data/2" do
    test "filters data with equals condition" do
      data = [1, 2, 3, 2, 1]
      condition = {:equals, 2}

      assert {:ok, [2, 2]} = Transformer.filter_data(data, condition)
    end

    test "filters data with greater_than condition" do
      data = [1, 2, 3, 4, 5]
      condition = {:greater_than, 3}

      assert {:ok, [4, 5]} = Transformer.filter_data(data, condition)
    end

    test "filters data with less_than condition" do
      data = [1, 2, 3, 4, 5]
      condition = {:less_than, 3}

      assert {:ok, [1, 2]} = Transformer.filter_data(data, condition)
    end

    test "filters data with contains condition" do
      data = [["a", "b"], ["c", "d"], ["a", "c"]]
      condition = {:contains, "a"}

      assert {:ok, [["a", "b"], ["a", "c"]]} = Transformer.filter_data(data, condition)
    end

    test "filters data with matches condition" do
      data = ["hello", "world", "hi"]
      condition = {:matches, ~r/h/}

      assert {:ok, ["hello", "hi"]} = Transformer.filter_data(data, condition)
    end

    test "filters data with custom function" do
      data = [1, 2, 3, 4, 5]
      condition = fn x -> rem(x, 2) == 0 end

      assert {:ok, [2, 4]} = Transformer.filter_data(data, condition)
    end

    test "requires list input for filter" do
      assert {:error, _} = Transformer.filter_data("not_a_list", {:equals, "value"})
    end

    test "handles filter errors" do
      data = [1, 2, 3]
      failing_condition = fn _x -> raise "Filter error" end

      assert {:error, _} = Transformer.filter_data(data, failing_condition)
    end
  end
end
