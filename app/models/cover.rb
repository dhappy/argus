class Cover 
  include Neo4j::ActiveNode
  property :mimetype, type: String
  property :cid, type: String
  property :url, type: String
end
