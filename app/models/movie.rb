class Movie 
  include Neo4j::ActiveNode
  property :by, type: String
  property :title, type: String
  property :copyright, type: String
  property :alias, type: String
  property :types, type: String
  include Neo4j::Timestamps

  serialize :types, array: true

  has_one :out, :repo, type: :RPO, model_class: :Repository
  has_one :in, :creators, type: :CRTR, model_class: :Creators
  has_many :in, :nominations, rel_class: :Nominated, unique: true
  has_many :in, :series, rel_class: :Contains, unique: true

  def to_s
    "#{self.title} by #{self.creators&.name}"
  end
end

