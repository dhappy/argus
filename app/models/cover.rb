class Cover 
  include Neo4j::ActiveNode
  property :mimetype, type: String
  property :ipfsID, type: String
  property :url, type: String
end
