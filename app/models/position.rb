class Position
  include ActiveGraph::Node

  has_one :out, :equals, type: :EQUALS, model_class: [:Book, :Creators]
  has_many :in, :parents, rel_class: :Context, unique: { on: [:name] }
  has_many :out, :children, rel_class: :Context, unique: { on: [:name] }
end
