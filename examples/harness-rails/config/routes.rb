Rails.application.routes.draw do
  root "harness#index"
  get "/healthz", to: "harness#healthz"
  get "/secret",  to: "harness#secret"
  get "/counter", to: "harness#counter"

  # Rails' own check, kept as an alternate health path.
  get "up" => "rails/health#show", as: :rails_health_check
end
