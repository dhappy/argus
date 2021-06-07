class Root
  include ActiveGraph::Node

  has_many :out, :children, rel_class: :Context, unique: { on: [:name] }
end
