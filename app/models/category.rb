class Category 
  include Neo4j::ActiveNode
  property :title, type: String

  has_many :out, :nominees, rel_class: :Nominated, unique: true
end
