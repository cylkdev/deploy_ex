defmodule Mix.Tasks.DeployEx.Ping do
  use Mix.Task

  @shortdoc "Pings the deploy_ex server"
  @moduledoc """
  Returns pong.

  ## Example
  ```bash
  mix deploy_ex.ping
  ```
  """

  def run(_args) do
    IO.puts("pong")
  end
end
