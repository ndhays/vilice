# This file is used by Rack-based servers to start the application.

require_relative "config/environment"

# Start the boot-time, non-HTTP knobs (memory balloon, crash timer) here so they fire only
# for the server — not for rake/console. See app/lib/harness.rb.
Harness.start_background!

run Rails.application
Rails.application.load_server
