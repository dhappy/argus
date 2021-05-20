class Award 
  include ActiveGraph::Node
  property :title, type: String
  property :shortname, type: String
  property :isfdbID, type: Integer

  has_many :out, :years, type: :YR, unique: true
end
