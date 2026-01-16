defmodule DeployEx.ReleaseConfigLoader do
  alias DeployEx.AwsSecretsManager

  def load_database_configs(opts) do
    path = Keyword.get(opts, :path, "./deploys/terraform/database/.generated/*.db.json")
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

  # def load_release_environment_variables(opts) do
  #   with {:ok, resource_configs} <- load_terraform_resource_configs(opts),
  #        {:ok, conn_params} <- conn_params_from_resource_configs(resource_configs) do
  #     case opts[:only] do
  #       nil -> {:ok, Map.values(conn_params)}
  #       keys -> {:ok, conn_params |> Map.take(List.wrap(keys)) |> Map.values()}
  #     end
  #   end
  # end

  # defp conn_params_from_resource_configs(resource_configs) do
  #   Enum.reduce_while(resource_configs, {:ok, %{}}, fn resource, {:ok, acc} ->
  #     case build_db_conn_params(resource) do
  #       {:ok, env_vars} -> {:cont, {:ok, Map.put(acc, resource.identifier, env_vars)}}
  #       e -> {:halt, e}
  #     end
  #   end)
  # end

  # defp build_db_conn_params(resource) do
  #   with {:ok, password} <- get_password_from_secret_manager(resource.master_user_secret_arn) do
  #     env_args = resource.env

  #     env_vars =
  #       %{}
  #       |> Map.put(env_args.endpoint.key, env_args.endpoint.value)
  #       |> Map.put(env_args.database.key, env_args.database.value)
  #       |> Map.put(env_args.username.key, env_args.username.value)
  #       |> Map.put(env_args.port.key, env_args.port.value)
  #       |> Map.put(env_args.password.key, password)

  #     {:ok, env_vars}
  #   end
  # end

  # defp get_password_from_secret_manager(secret_arn) do
  #   with {:ok, payload} <- AwsSecretsManager.get_secret_value(secret_arn) do
  #     case Jason.decode!(payload) do
  #       %{"password" => password} -> {:ok, password}
  #       term -> {:error, ErrorMessage.bad_request("Invalid secret payload: #{inspect(term)}")}
  #     end
  #   end
  # end

  # def load_terraform_resource_configs(opts \\ []) do
  #   with {:ok, release_configs} <- parse_release_config_file(opts),
  #        {:ok, generated_resources} <-
  #          generated_resources_for_release_configs(release_configs, opts) do
  #     {:ok,
  #      Enum.map(release_configs, fn rel ->
  #        identifier = rel.identifier
  #        tf_state = Map.fetch!(generated_resources, identifier)

  #        %{
  #          master_user_secret_arn: tf_state.master_user_secret_arn,
  #          identifier: identifier,
  #          env: %{
  #            database: %{key: rel.schema.database, value: tf_state.database},
  #            endpoint: %{key: rel.schema.endpoint, value: tf_state.endpoint},
  #            username: %{key: rel.schema.username, value: tf_state.username},
  #            port: %{key: rel.schema.port, value: tf_state.port},
  #            password: %{key: rel.schema.password, value: nil}
  #          }
  #        }
  #      end)}
  #   end
  # end

  # defp generated_resources_for_release_configs(release_configs, opts) do
  #   dir = working_dir(opts)

  #   Enum.reduce_while(release_configs, {:ok, %{}}, fn release_config, {:ok, acc} ->
  #     identifier = release_config.identifier
  #     file = Path.join(dir, ".generated/#{identifier}.db.json")

  #     case parse_generated_resource_file(file) do
  #       {:ok, values} ->
  #         {:cont, {:ok, Map.put(acc, identifier, values)}}

  #       {:error, reason} ->
  #         {:halt, {:error, reason}}
  #     end
  #   end)
  # end

  # defp parse_generated_resource_file(file) do
  #   if File.exists?(file) do
  #     file |> File.read!() |> parse_generated_resource_json()
  #   else
  #     {:error, ErrorMessage.bad_request("Database release varfile not found: #{file}")}
  #   end
  # end

  # defp parse_generated_resource_json(data) do
  #   with {:ok,
  #         %{
  #           "master_user_secret_arn" => master_user_secret_arn,
  #           "database" => database,
  #           "endpoint" => endpoint,
  #           "username" => username,
  #           "port" => port
  #         }} <- Jason.decode(data) do
  #     {:ok,
  #      %{
  #        master_user_secret_arn: master_user_secret_arn,
  #        database: database,
  #        endpoint: endpoint,
  #        username: username,
  #        port: String.to_integer(port)
  #      }}
  #   else
  #     {:ok, term} ->
  #       {:error, ErrorMessage.bad_request("Invalid release config: #{inspect(term)}")}

  #     {:error, reason} ->
  #       {:error, ErrorMessage.bad_request("Failed to parse release config: #{reason}")}
  #   end
  # end

  # defp parse_release_config_file(opts) do
  #   dir = working_dir(opts)
  #   file = Keyword.get(opts, :config_file, Path.join(dir, "rel.config.json"))

  #   with :ok <- ensure_config_file_exists(file),
  #        {:ok, data} <- File.read(file),
  #        {:ok, serialized} <- Jason.decode(data) do
  #     deserialize_release_configs(serialized)
  #   else
  #     {:ok, data} ->
  #       {:error, ErrorMessage.bad_request("Invalid release config: #{inspect(data)}")}

  #     {:error, reason} ->
  #       {:error, ErrorMessage.bad_request("Failed to parse release config: #{reason}")}
  #   end
  # end

  # defp deserialize_release_configs(entries) do
  #   with {:ok, values} <-
  #          Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, acc} ->
  #            case entry do
  #              %{
  #                "identifier" => identifier,
  #                "schema" => %{
  #                  "username" => username,
  #                  "database" => database,
  #                  "endpoint" => endpoint,
  #                  "port" => port,
  #                  "password" => password
  #                }
  #              } ->
  #                config = %{
  #                  identifier: identifier,
  #                  schema: %{
  #                    username: username,
  #                    database: database,
  #                    endpoint: endpoint,
  #                    port: port,
  #                    password: password
  #                  }
  #                }

  #                {:cont, {:ok, [config | acc]}}

  #              term ->
  #                {:halt,
  #                 {:error, ErrorMessage.bad_request("Invalid release config: #{inspect(term)}")}}
  #            end
  #          end) do
  #     {:ok, Enum.reverse(values)}
  #   end
  # end

  # defp working_dir(opts) do
  #   Keyword.get(opts, :dir, "./deploys/terraform/database/")
  # end

  # defp ensure_config_file_exists(path) do
  #   if File.exists?(path) do
  #     :ok
  #   else
  #     {:error, ErrorMessage.bad_request("Database release config file not found: #{path}")}
  #   end
  # end
end
