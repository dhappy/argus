class Category 
  include ActiveGraph::Node
  property :title, type: String

  has_many :out, :nominees, rel_class: :Nominated, unique: true
end
