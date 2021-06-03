class Year 
  include ActiveGraph::Node
  property :number, type: Integer

  has_many :out, :categories, type: :FOR, unique: true
end
