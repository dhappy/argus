class Context 
  include ActiveGraph::Node
  property :name, type: String
  property :type, type: String
  include ActiveGraph::Timestamps
  
  has_many :in, :contexts, type: :SUB
  has_many :out, :subcontexts, type: :SUB, model_class: :Context, unique: true
  has_many :out, :for, type: :FOR, model_class: [:Book, :Movie], unique: true
end
