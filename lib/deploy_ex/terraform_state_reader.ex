defmodule DeployEx.TerraformStateReader do
  @moduledoc """
  Parses Terraform JSON state and finds resources by address components.
  """

  def read(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  @doc """
  Finds a resource by its components.

  ## Examples

      state = TerraformState.read("tf.json")
      TerraformState.get_resource(state, ["app_security_group", "sg"], "aws_security_group", "this_name_prefix", 0)
  """
  def get_resource(state, modules, type, name, index \\ nil) do
    address = build_address(modules, type, name, index)

    state
    |> get_in(["values", "root_module"])
    |> collect_all_resources()
    |> Enum.find(fn resource -> resource["address"] == address end)
  end

  def list_resources(state, opts \\ []) do
    resources =
      state
      |> get_in(["values", "root_module"])
      |> collect_all_resources()

    case Keyword.get(opts, :type) do
      nil -> resources
      type -> Enum.filter(resources, fn r -> r["type"] == type end)
    end
  end

  defp build_address(modules, type, name, index) do
    module_path = modules |> Enum.map(&"module.#{&1}") |> Enum.join(".")

    case {module_path, index} do
      {"", nil} -> "#{type}.#{name}"
      {"", idx} -> "#{type}.#{name}[#{idx}]"
      {mp, nil} -> "#{mp}.#{type}.#{name}"
      {mp, idx} -> "#{mp}.#{type}.#{name}[#{idx}]"
    end
  end

  defp collect_all_resources(nil), do: []

  defp collect_all_resources(module) do
    direct_resources = Map.get(module, "resources", [])

    child_resources =
      module
      |> Map.get("child_modules", [])
      |> Enum.flat_map(&collect_all_resources/1)

    direct_resources ++ child_resources
  end
end
