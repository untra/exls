# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# By default, the umbrella project as well as each child
# application will require this configuration file, ensuring
# they all use the same configuration. While one could
# configure all applications here, we prefer to delegate
# back to each application for organization purposes.
# import_config "../apps/*/config/config.exs"

config :logger,
  handle_otp_reports: true,
  handle_sasl_reports: true,
  backends: [{ExLS.LanguageServer.LoggerBackend, :lsp_logger_backend}]

# config :elixirls, ip: {127,0,0,1}, port: 6666
# Sample configuration (overrides the imported configuration above):
#
#     config :logger, :console,
#       level: :info,
#       format: "$date $time [$level] $metadata$message\n",
#       metadata: [:user_id]
