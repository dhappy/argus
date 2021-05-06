class Award 
  include ActiveGraph::Node
  property :title, type: String
  property :shortname, type: String

  has_many :out, :years, type: :YR, unique: true
end
