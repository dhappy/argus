class Context 
  include Neo4j::ActiveNode
  property :name, type: String
  property :created_at, type: DateTime
  property :updated_at, type: DateTime

  has_many :out, :contexts, type: :SUB, unique: true
  has_many :out, :for, type: :FOR, model_class: :Book
end
