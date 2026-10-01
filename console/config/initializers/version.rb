# The fleet's version, read from the monorepo's single VERSION file so the app
# and the CLI never drift. Shown on the Settings page.
ViliceConsole::VERSION = Rails.root.join("..", "VERSION").read.strip.freeze
