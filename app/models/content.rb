class Content 
  include Neo4j::ActiveNode
  property :mimetype, type: String
  property :ipfs_id, type: String
  property :url, type: String
  include Neo4j::Timestamps
end
