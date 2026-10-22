require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ViliceConsole
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Secrets come from the deployment, never from the repo
    # (decisions/secrets-come-from-the-deployment.md). Rails reads SECRET_KEY_BASE from
    # the environment itself; the keys that encrypt Machine#ssh_private_key are read
    # here. Where one is unset, Rails falls back to a local, untracked credentials file —
    # which is how development works.
    %w[primary_key deterministic_key key_derivation_salt].each do |name|
      value = ENV["ACTIVE_RECORD_ENCRYPTION_#{name.upcase}"]
      config.active_record.encryption.public_send("#{name}=", value) if value.present?
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
