class Book 
  include Neo4j::ActiveNode
  property :title, type: String
  property :author, type: String
  include Neo4j::Timestamps

  has_many :in, :contexts, type: :FOR
  has_one :out, :cover, type: :CVR, model_class: :Content
  has_one :out, :content, type: :DAT
  has_many :out, :versions, type: :PUB
end
