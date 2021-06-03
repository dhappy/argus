class Creators
  include ActiveGraph::Node
  property :name, type: String
  property :legalname, type: String
  property :aliases, type: String
  property :did, type: String
  include ActiveGraph::Timestamps

  serialize :aliases, array: true

  has_many :out, :books, type: :CREATED
  has_many :out, :movies, type: :CREATED

  def names; self.name.split(' & '); end
end
