class Version 
  include Neo4j::ActiveNode
  property :isbn, type: String
  include Neo4j::Timestamps

  has_one :out, :cover, type: :CVR, model_class: :Cover
  has_one :in, :book, type: :PUB
end
