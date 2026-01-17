defmodule DeployEx.ReleaseConfigLoader do
  alias DeployEx.AwsSecretsManager

  def load_database_configs(opts) do
    path = Keyword.get(opts, :path, "./deploys/terraform/.generated/*.db.json")
    config_file = opts[:config_file]
    schema_file = opts[:schema_file]

    cond do
      not is_nil(config_file) ->
        if is_nil(schema_file) do
          {:error,
           ErrorMessage.bad_request(
             "schema_file option is required when config_file option is set"
           )}
        else
          parse_database_config(config_file, schema_file)
        end

      not is_nil(schema_file) ->
        if is_nil(config_file) do
          {:error,
           ErrorMessage.bad_request(
             "config_file option is required when schema_file option is set"
           )}
        else
          parse_database_config(config_file, schema_file)
        end

      true ->
        parse_all_database_configs(path)
    end
  end

  def parse_all_database_configs(path) do
    path
    |> Path.wildcard()
    |> Enum.reduce_while({:ok, []}, fn config_file, {:ok, acc} ->
      schema_file = String.replace(config_file, ".db.json", ".schema.json")

      case parse_database_config(config_file, schema_file) do
        {:ok, payload} -> {:cont, {:ok, [payload | acc]}}
        e -> {:halt, e}
      end
    end)
    |> then(fn
      {:ok, results} -> {:ok, Enum.reverse(results)}
      e -> e
    end)
  end

  def parse_database_config(config_file, schema_file) when is_binary(schema_file) do
    with {:ok, config} <- parse_generated_database_config_file(config_file),
         {:ok, schema} <- parse_schema_file(schema_file) do
      build_database_config(config, schema)
    end
  end

  def build_database_config(config, schema) do
    with {:ok, password} <- resolve_db_config_password(config) do
      {:ok,
       %{
         identifier: config.identifier,
         environment: %{
           endpoint: %{
             key: schema.environment.endpoint,
             value: config.endpoint
           },
           port: %{
             key: schema.environment.port,
             value: config.port
           },
           database: %{
             key: schema.environment.database,
             value: config.database
           },
           username: %{
             key: schema.environment.username,
             value: config.username
           },
           password: %{
             key: schema.environment.password,
             value: password
           }
         }
       }}
    end
  end

  defp resolve_db_config_password(config) do
    if Map.has_key?(config, :master_user_secret_arn) do
      with {:ok, credentials} <-
             get_database_credentials_via_secret_manager(config.master_user_secret_arn) do
        {:ok, credentials.password}
      end
    else
      {:ok, config[:password]}
    end
  end

  defp parse_generated_database_config_file(data_file) do
    with {:ok, raw_data} <- read_file(data_file),
         {:ok, payload} <- decode_json(raw_data) do
      case payload do
        %{
          "identifier" => identifier,
          "master_user_secret_arn" => master_user_secret_arn,
          "database" => database,
          "endpoint" => endpoint,
          "username" => username,
          "port" => port
        } ->
          {:ok,
           %{
             identifier: identifier,
             master_user_secret_arn: master_user_secret_arn,
             database: database,
             endpoint: endpoint,
             username: username,
             port: port
           }}

        term ->
          {:error,
           ErrorMessage.internal_server_error("failed to parse generated database config", %{
             data: term
           })}
      end
    end
  end

  defp parse_schema_file(schema_file) do
    with {:ok, raw_schema} <- read_file(schema_file),
         {:ok, payload} <- decode_json(raw_schema) do
      case payload do
        %{"environment" => env} ->
          {:ok,
           %{
             environment: %{
               username: env["username"],
               database: env["database"],
               endpoint: env["endpoint"],
               port: env["port"],
               password: env["password"]
             }
           }}

        term ->
          {:error, ErrorMessage.internal_server_error("failed to parse schema", %{data: term})}
      end
    end
  end

  defp decode_json(data) do
    case Jason.decode(data) do
      {:ok, data} ->
        {:ok, data}

      {:error, reason} ->
        {:error,
         ErrorMessage.internal_server_error("failed to decode json", %{data: data, reason: reason})}
    end
  end

  defp read_file(file) do
    case File.read(file) do
      {:ok, data} ->
        {:ok, data}

      {:error, reason} ->
        {:error,
         ErrorMessage.internal_server_error("failed to read file", %{file: file, reason: reason})}
    end
  end

  # ---

  def get_database_credentials("aws", opts) do
    with {:ok, secret_arn} <- get_secret_arn(opts) do
      get_database_credentials_via_secret_manager(secret_arn)
    end
  end

  def get_database_credentials(source, _opts) do
    {:error, ErrorMessage.bad_request("invalid request", %{source: source})}
  end

  defp get_secret_arn(opts) do
    case Keyword.get(opts, :secret_arn) do
      nil -> {:error, ErrorMessage.bad_request("secret_arn is required")}
      secret_arn -> {:ok, secret_arn}
    end
  end

  def get_database_credentials_via_secret_manager(secret_arn) do
    with {:ok, payload} <- AwsSecretsManager.get_secret_value(secret_arn) do
      case Jason.decode(payload) do
        {:ok, %{"username" => username, "password" => password}} ->
          {:ok, %{username: username, password: password}}

        term ->
          {:error, ErrorMessage.bad_request("invalid secret payload", %{payload: term})}
      end
    end
  end
end
