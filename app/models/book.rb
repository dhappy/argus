class Book 
  include Neo4j::ActiveNode
  property :title, type: String
  property :author, type: String
  property :created_at, type: DateTime
  property :updated_at, type: DateTime

  has_one :out, :cover, type: :CVR, model_class: :Content
  has_one :out, :content, type: :DAT
end
