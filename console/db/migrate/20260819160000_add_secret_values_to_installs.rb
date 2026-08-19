# The values behind the names an app declares. Held **encrypted at rest** (the same
# Active Record Encryption that protects a Machine's private key) and resent on every
# deploy, so a deploy is self-contained: no set-once ordering, no dangling secret waiting
# for an app (decisions/declarative-deploy.md).
#
# Per **Install**, not per App: staging and production are two placements of one app and
# do not share a database password. The App declares the names; the Install holds what
# they are worth.
class AddSecretValuesToInstalls < ActiveRecord::Migration[8.1]
  def change
    add_column :installs, :secret_values, :text
  end
end
