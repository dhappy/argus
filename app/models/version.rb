class Version 
  include ActiveGraph::Node
  property :isbn, type: String
  include ActiveGraph::Timestamps

  has_one :out, :cover, type: :CVR, model_class: :Cover
  has_one :in, :book, type: :PUB
end
