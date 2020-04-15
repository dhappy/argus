Rails.application.routes.draw do
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html
  root to: 'context#index'
  get '/view/:uuid', to: 'book#show'
  get '/review', to: 'pages#review'
  get '/*path', to: 'context#index', constraints: { id: /.+/ }
end
