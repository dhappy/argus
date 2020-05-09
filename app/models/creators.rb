class Creators
  include Neo4j::ActiveNode
  property :name, type: String
  property :legalName, type: String
  property :aliases, type: String
  include Neo4j::Timestamps

  serialize :aliases, array: true

  has_many :in, :books, type: :BOOK
  has_many :in, :movies, type: :MVIE 

  def names; self.name.split(' & '); end
end
