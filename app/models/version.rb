class Version 
  include ActiveGraph::Node
  property :isbn, type: String
  include ActiveGraph::Timestamps

  has_one :out, :cover, type: :COVER, model_class: :Cover
  has_one :in, :book, type: :PUBLICATION
end
