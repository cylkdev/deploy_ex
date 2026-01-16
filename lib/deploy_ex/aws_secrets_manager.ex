defmodule DeployEx.AwsSecretsManager do
  @moduledoc """
  Module for interacting with AWS Secrets Manager
  """

  def get_secret_value(secret_name) do
    case secret_name
         |> ExAws.SecretsManager.get_secret_value()
         |> ExAws.request(region: DeployEx.Config.aws_region()) do
      {:ok, %{"SecretString" => value}} ->
        {:ok, value}

      {:ok, %{"SecretBinary" => value}} ->
        {:ok, Base.decode64!(value)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
