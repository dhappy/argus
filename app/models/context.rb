class Context
  include ActiveGraph::Relationship
  from_class :any
  to_class   :any
  type :CHILD

  property :name, type: String
end
