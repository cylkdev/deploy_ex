defmodule Mix.Tasks.DeployEx.Database.Config.Build do
  use Mix.Task

  @shortdoc "Builds database config for an application"
  @moduledoc """
  mix deploy_ex.database.config.build
  mix deploy_ex.database.config.build --config-file="./deploys/terraform/database/.generated/requis_backend.db.json" --schema-file="./deploys/terraform/database/.generated/requis_backend.schema.json"
  """
  def run(args) do
    Application.ensure_all_started(:hackney)
    Application.ensure_all_started(:telemetry)
    Application.ensure_all_started(:ex_aws)

    {opts, _args} =
      OptionParser.parse!(args,
        aliases: [],
        switches: [
          path: :string,
          config_file: :string,
          schema_file: :string
        ]
      )

    with {:ok, payload} <-
           DeployEx.ReleaseConfigLoader.load_database_configs(opts) do
      payload
      |> Jason.encode!(pretty: true)
      |> IO.puts()

      :ok
    else
      {:error, reason} ->
        Mix.shell().error(inspect(reason))
        System.halt(1)
    end
  end
end
