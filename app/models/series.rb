class Series 
  include ActiveGraph::Node
  property :title, type: String
  property :parents, type: String
  property :rank, type: Float
  property :isfdbID, type: String

  serialize :parents, array: true

  has_many :in, :parents, rel_class: :Contains, unique: true
  has_many :out, :series, rel_class: :Contains, unique: true
  has_many :out, :contains, rel_class: :Contains, unique: true
end
