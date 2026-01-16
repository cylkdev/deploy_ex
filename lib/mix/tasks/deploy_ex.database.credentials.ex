defmodule Mix.Tasks.DeployEx.Database.Credentials do
  use Mix.Task

  @shortdoc "Displays database config for an application"
  @moduledoc """
  mix deploy_ex.database.credentials --source="aws" --secret-arn="arn:aws:secretsmanager:us-west-1:750872578221:secret:rds!db-522f214f-8af0-4cac-b7db-b8bb411b598d-mcTxKg"
  """
  def run(args) do
    Application.ensure_all_started(:hackney)
    Application.ensure_all_started(:telemetry)
    Application.ensure_all_started(:ex_aws)

    {opts, _args} =
      OptionParser.parse!(args,
        aliases: [],
        switches: [
          type: :string,
          source: :string,
          secret_arn: :string
        ]
      )

    opts = normalize_only_opts(opts)

    source = opts[:source]

    if is_nil(source), do: Mix.raise("source is required")

    with {:ok, payload} <- DeployEx.ReleaseConfigLoader.get_database_credentials(source, opts) do
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

  defp normalize_only_opts(opts) do
    case opts[:only] do
      nil -> opts
      only -> Keyword.put(opts, :only, String.split(only, ",", trim: true))
    end
  end
end
