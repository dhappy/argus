class Content
  include ActiveGraph::Node
  property :mimetype, type: String
  property :ipfs_id, type: String
  property :url, type: String
  include ActiveGraph::Timestamps

  has_many :in, :versions, type: :CVR
end
