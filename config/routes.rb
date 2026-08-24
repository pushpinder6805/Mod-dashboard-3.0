# frozen_string_literal: true

MashReviewDashboard::Engine.routes.draw do
  get "/items" => "items#index"
  get "/items/:id/content" => "items#content"
  put "/items/:id/content" => "items#update_content"
  get "/items/:id" => "items#show"
  put "/items/:id/status" => "items#update_status"
  put "/items/:id/assignment" => "items#update_assignment"

  post "/items/:item_id/notes" => "notes#create"
  put "/notes/:id" => "notes#update"

  get "/migration/preview" => "migration#preview"
  post "/migration/backfill" => "migration#backfill"
  post "/migration/local-storage" => "migration#import_local_storage"
end

Discourse::Application.routes.draw do
  mount ::MashReviewDashboard::Engine, at: "/mash-review-dashboard"
end
