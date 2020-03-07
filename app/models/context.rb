class Context 
  include Neo4j::ActiveNode
  property :name, type: String
  property :type, type: String
  property :created_at, type: DateTime
  property :updated_at, type: DateTime

  has_many :in, :contexts, type: :SUB
  has_many :out, :subcontexts, type: :SUB, model_class: :Context, unique: true
  has_many :out, :for, type: :FOR, model_class: :Book, unique: true
end
