Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

  # Reveal health status on /up that returns 200 if the app boots with no exceptions.
  get "up" => "rails/health#show", as: :rails_health_check

  # Status — the home page: only what needs the operator.
  root "home#index"

  # Record — the running record of everything across the fleet.
  get "record", to: "record#index"

  # Access — the rights ledger: who may act on which box, at what scope. Read
  # straight from each box's authorized_keys through `steward actors`.
  get "access", to: "access#index"
  # Re-read every box's ledger, bypassing the 30s cache. A POST because it opens an
  # SSH connection to every box in the fleet — a GET must be safe to repeat unasked,
  # and Turbo prefetches links on hover. Same rule as machines#refresh.
  post "access/refresh", to: "access#refresh", as: :refresh_access

  # Apps — placement: this app, on these boxes. Top-level, because a placement
  # doesn't belong to a client (decisions/console-layers.md). A project is optional
  # context, passed as `?project_id=` the way machines#new already takes one.
  # `edit`/`update` reach the **intention only** (count + exposure), never the spec. State
  # a different number and the gap moves; nothing is deployed or removed by saying so
  # (decisions/drift-is-surfaced-never-closed.md — changing an intention must not touch a box).
  resources :apps, only: %i[ index new create show edit update ] do
    # The values behind the names the app declares. Its own action rather than part of
    # `update`, which is deliberately narrow — that one restates the *intention* and
    # touches nothing that gets deployed. This is configuration, and it is the one place
    # a secret value enters the console.
    member { patch :configure }
    # Place this app on one more box — the act that closes a placement gap. Never
    # automatic: the console shows the gap and a person presses the button
    # (decisions/drift-is-surfaced-never-closed.md). Scaling *down* needs no route of
    # its own — that's the existing `remove` verb on a target.
    resources :placements, only: %i[ new create ]
  end

  # Projects → Project view (apps, machines, activity). The project lens over
  # placement, not its container.
  resources :projects, only: %i[ index show new create edit update destroy ] do
    member do
      # Star / unstar — a recorded control-plane act (focus lens).
      patch :star
    end
    # Attach an existing fleet machine to this project — the M:N edge (the
    # ProjectMachine join enforces Decision 1). Creating a *new* machine is still
    # machines#new?project_id=. (Detach is a planned follow-up — needs row-context UI.)
    resources :project_machines, only: %i[ create ]
    # Labels — a control-plane act with no box; recorded with human attribution.
    resources :labels, only: %i[ create destroy ], shallow: true
  end

  # App Library — the curated directory of installable app definitions (no app
  # action here; the library is a directory, not a launcher).
  resources :app_templates do
    # The library as a portable manifest, and bulk curation (the counterweight to
    # additive import). See decisions/open/app-library.md.
    collection do
      get    :export
      post   :import
      delete :remove_selected
    end
    # Releases of the app; one is `latest` (the app default).
    resources :versions, only: %i[ create destroy ] do
      member { patch :latest }
      # Ask the registry what a tag points at, and hand the answer back to the form.
      # A read, not an act: it writes nothing and creates nothing (app/services/registry.rb).
      collection { post :resolve }
    end
    # Generic key/value metadata, like projects/machines.
    resources :labels, only: %i[ create destroy ], shallow: true
  end

  # All Machines — the fleet, the per-machine deep dive, and onboarding (new/create).
  resources :machines, only: %i[ index show new create destroy ] do
    # Apps on this box, as the box sees them. Machine-scoped on purpose: this is
    # the machine view's own surface, and it works with no Project and no App —
    # the AppConfig is sent to the box and discarded, and the box's record is the
    # only record. See blueprint/console/interface.md.
    resources :apps, only: %i[ new create destroy ], module: :machines, as: :box_apps
    resources :labels, only: %i[ create destroy ], shallow: true
    member do
      # Observe — re-read the machine's live status, bypassing the 30s cache. It
      # reads the box and changes nothing *there*, but it opens an SSH connection
      # and projects the result onto our own columns, so it is a POST: a GET must
      # be safe to repeat unasked, and Turbo prefetches links on hover.
      post :refresh
      # The half of the machine page that needs the box, loaded into a frame after the
      # rest of the page is on screen. A read, and the same cached reads as before.
      get :live
      # Sharing & ownership (the Access panel) — set the sharing mode, transfer or
      # release the owner. machine-ownership.md.
      patch :sharing
      patch :transfer
    end
    # The sharing allowlist (sharing = list): which projects may pick up the box.
    resources :grants, only: %i[ create destroy ], controller: "machine_grants"
    # Mutate — the witnessed ceremony: `new` previews the exact record line,
    # `create` records it (pending), runs it over scoped SSH, and settles it.
    resource :mutation, only: %i[ new create ]
    # Observe — an app's log tail from this box. A GET because it is a plain read: it
    # writes nothing, not even the projection `refresh` makes, so it is safe to repeat
    # and worth being able to reload. (Turbo prefetch is off for the whole app, so a
    # GET does not fire an SSH connection on hover.)
    resource :logs, only: :show, controller: "logs"
  end

  # Settings.
  resource :settings, only: %i[ show update ], controller: "settings"
  # Change the signed-in user's own password.
  patch "settings/password", to: "settings#change_password", as: :settings_password
  # This operator's own theme and mode. Personal, not fleet policy — and reachable
  # from the rail's toggle as well as the Settings form.
  patch "settings/appearance", to: "settings#appearance", as: :settings_appearance
  # Dev-only: wipe all fleet data for a clean slate (guarded in the controller).
  delete "settings/data", to: "settings#destroy_data", as: :settings_data
end
