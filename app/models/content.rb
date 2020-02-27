class Content 
  include Neo4j::ActiveNode
  property :mimetype, type: String
  property :ipfs_id, type: String
  property :created_at, type: DateTime
  property :updated_at, type: DateTime
end
