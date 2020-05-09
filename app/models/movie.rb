class Movie 
  include Neo4j::ActiveNode
  property :by, type: String
  property :title, type: String
  property :copyright, type: String
  property :alias, type: String
  property :types, type: String
  include Neo4j::Timestamps

  serialize :types, array: true

  has_many :in, :contexts, type: :FOR
  has_one :out, :cover, type: :CVR, model_class: :Content
  has_many :in, :nominations, rel_class: :Nominated, unique: true
  has_many :in, :series, rel_class: :Contains, unique: true
end
