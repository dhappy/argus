class Movie 
  include ActiveGraph::Node
  property :by, type: String
  property :title, type: String
  property :published_at, type: String
  property :alias, type: String
  property :types, type: String
  property :isfdbID, type: Integer
  include ActiveGraph::Timestamps

  serialize :types, array: true

  has_one :out, :repo, type: :REPO, model_class: :Repository
  has_one :in, :creators, type: :CREATED, model_class: :Creators
  has_many :in, :nominations, rel_class: :Nominee, unique: true
  has_many :in, :series, rel_class: :Contains, unique: true

  def to_s
    "#{self.title} by #{self.creators&.name}"
  end
end

