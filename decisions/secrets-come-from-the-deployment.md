# Secrets come from the deployment, never from the repo

> Decided 2026-10-22. Code: `console/config/application.rb`,
> `console/config/environments/test.rb`. Settles "Keys out of core" in
> [`open/console-open-questions.md`](open/console-open-questions.md).

## The decision

**The console's repository carries no secrets, encrypted or not.** Each deployment
supplies its own:

- **Production** reads `SECRET_KEY_BASE` and `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`,
  `…_DETERMINISTIC_KEY` and `…_KEY_DERIVATION_SALT` from its environment. Rails reads the
  first itself; `application.rb` reads the other three. With none set it refuses to boot.
- **Development** keeps a credentials file, made locally (`bin/rails db:encryption:init`,
  then `bin/rails credentials:edit`) and gitignored with its master key. Where an
  environment variable is unset, Rails falls back to it.
- **Tests** use fixed keys of their own, public on purpose, in `environments/test.rb`.

`config/credentials.yml.enc` and `config/credentials/` are in `.gitignore` and
`.dockerignore`, so a local copy reaches neither a commit nor an image.

## Why

The three encryption keys protect `Machine#ssh_private_key` — operate keys to real
boxes. A committed `credentials.yml.enc` is safe only while its master key never leaks,
and in a public repository a leak at any time also opens every past version in history.
It is no use to anyone else either: another operator cannot decrypt it and has to replace
it. Mastodon and Discourse ship no credentials for the same reason.

It also fixes who needs the master key. The tests used to borrow it, so the build
machine, which runs third-party code all day, had to hold it to run the tests. Now the
tests need nothing and the image build needs nothing (`SECRET_KEY_BASE_DUMMY` compiles
the assets). Only the running console holds the keys, given to it when it is deployed.

## What happened to the committed keys

`credentials.yml.enc` was committed once (339c44d) and stays in history; rewriting
history breaks every clone and buys little. Those keys only ever protected development
data, and they stay there. **Production starts with fresh keys** that have never been in
git — no production console existed when this was decided, so nothing has to be
re-encrypted.

## Roads not taken

- **Per-environment credentials** (`config/credentials/production.yml.enc`, its key only
  on the deploy host). It keeps an encrypted file of secrets in the repo, which is the
  thing being removed, and gives a public project a file only one operator can open.
- **Fixed public keys in development too,** like the tests. A developer's database holds
  real machine keys; public keys would protect them with nothing.
- **Copy `master.key` to the build machine.** It makes the errors go away by putting the
  most valuable secret on the machine with the most foreign code.
