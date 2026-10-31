Rails.application.routes.draw do
  resources :venues, only: [:show] do
    resources :shifts, only: [:index, :show, :create] do
      resource :cancellation, only: [:create]
    end
  end
end
