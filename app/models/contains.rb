class Contains
  include Neo4j::ActiveRel
  from_class :Series
  to_class   [:Book, :Movie, :Series]
  type :HAS

  property :rank, type: String
end