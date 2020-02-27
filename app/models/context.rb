class Context 
  include Neo4j::ActiveNode
  property :name, type: String
  property :created_at, type: DateTime
  property :updated_at, type: DateTime

  has_many :out, :contexts, type: :SUB, unique: true
  has_one :out, :reference, type: :REF, model_class: :Book
end
