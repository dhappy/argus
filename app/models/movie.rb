class Movie 
  include Neo4j::ActiveNode
  property :by, type: String
  property :title, type: String
  include Neo4j::Timestamps

  has_many :in, :contexts, type: :FOR
  has_one :out, :cover, type: :CVR, model_class: :Content
  has_many :in, :nominations, rel_class: :Nomination, unique: true
end
