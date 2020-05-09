class Creator 
  include Neo4j::ActiveNode
  property :name, type: String
  property :legalName, type: String
  property :aliases, type: String



end
