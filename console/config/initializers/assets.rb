# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# Add additional assets to the asset load path.
# The two typefaces, vendored rather than fetched from a CDN: this app is meant to
# run on infrastructure you control, and a font CDN watches every page load.
# See blueprint/design/tokens.md.
Rails.application.config.assets.paths << Rails.root.join("app/assets/fonts")
