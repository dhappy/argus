class Cover 
  include ActiveGraph::Node
  property :mimetype, type: String
  property :cid, type: String
  property :url, type: String
  property :width, type: Integer
  property :height, type: Integer

  has_many :in, :versions, type: :CVR
end
