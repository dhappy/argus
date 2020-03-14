namespace :export do
  desc 'Export data to external sources'

  task(ipfs: :environment) do |t, args|
    q = Neo4j::ActiveBase.current_session.query(
      "MATCH path = (n)-[s:SUB*]->(m)-[f:FOR]->(o) WHERE n.name = '∅' RETURN DISTINCT path LIMIT 500"
    )
    q.each do |ret|
      nodes = ret.path.nodes
      nodes.shift # remove ∅
      book = nodes.pop
      path = nodes.map{ |n| n.properties[:name] }
      path += [
        "#{book.properties[:title]}, by #{book.properties[:author]}"
      ]
      # ToDo: IPFS::Client.default.mkdir(path + [name], parents: true)
      path.each{ |n| n&.gsub!('%', '%25')&.gsub!('/', '%2F') }
      basedir = "epubs-#{Time.now.iso8601}"
      datadir = "/#{basedir}/#{path.join('/')}"
      system('ipfs', 'files', 'mkdir', '-p', datadir)
      if book.content
        system('ipfs', 'files', 'cp', "/ipfs/#{book.content.ipfs_id}", "/#{datadir}/index.epub")
      end
      if book.cover
        filename = "cover.#{book.cover.mimetype}"
        system('ipfs', 'files', 'cp', "/ipfs/#{book.cover.ipfs_id}" "/#{datadir}/#{filename}")
      end
    end
  end
end