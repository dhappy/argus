class Contains
  include ActiveGraph::Relationship
  from_class :Series
  to_class   [:Book, :Movie, :Series]
  type :CONTAINS

  property :rank, type: String
end