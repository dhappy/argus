class Year 
  include Neo4j::ActiveNode
  property :number, type: Float

  has_many :out, :categories, type: :CAT, unique: true
end
