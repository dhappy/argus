class Book 
  include ActiveGraph::Node
  property :title, type: String
  property :types, type: String
  property :published_at, type: String
  include ActiveGraph::Timestamps

  serialize :types, array: true

  has_one :out, :repo, type: :RPO, model_class: :Repository
  has_many :out, :versions, type: :PUB
  has_one :in, :creators, type: :CRTR, model_class: :Creators
  has_many :in, :nominations, rel_class: :Nominated, unique: true
  has_many :in, :series, rel_class: :Contains, unique: true

  def to_s
    "#{self.title} by #{self.creators&.name}"
  end
end
