class Category 
  include ActiveGraph::Node
  property :title, type: String

  has_many :out, :nominees, rel_class: :Nominee, unique: true
end
