class Contains
  include ActiveGraph::Node
  from_class :Series
  to_class   [:Book, :Movie, :Series]
  type :HAS

  property :rank, type: String
end