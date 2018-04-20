# frozen_string_literal: true

Rails.application.routes.draw do
  root to: "documents#index"
  resources :documents
end
