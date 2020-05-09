class Creators
  include Neo4j::ActiveNode
  property :name, type: String
  property :legalName, type: String
  property :aliases, type: String
  include Neo4j::Timestamps

  serialize :aliases, array: true

  has_many :out, :books, type: :CRTR
  has_many :out, :movies, type: :CRTR 

  def names; self.name.split(' & '); end
end
