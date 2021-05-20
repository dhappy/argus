class Context
  include ActiveGraph::Relationship
  from_class :any
  to_class   :any
  type :CTX

  property :name, type: String
end
