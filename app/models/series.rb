class Series 
  include Neo4j::ActiveNode
  property :title, type: String
  property :parents, type: String



end
