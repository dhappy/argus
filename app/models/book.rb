class Book 
  include Neo4j::ActiveNode
  property :title, type: String
  property :authors, type: String
  property :alias, type: String
  property :types, type: String
  property :copyright, type: String
  include Neo4j::Timestamps

  #serialize :authors, array: true
  serialize :types, array: true

  has_many :in, :contexts, type: :FOR
  has_one :out, :cover, type: :CVR, model_class: :Content
  has_one :out, :repo, type: :RPO, model_class: :Content
  has_one :out, :content, type: :DAT
  has_many :out, :versions, type: :PUB
  has_many :in, :nominations, rel_class: :Nominated, unique: true
  has_many :in, :series, rel_class: :Contains, unique: true

  def to_s; "#{self.title} by #{self.authors}"; end
end
