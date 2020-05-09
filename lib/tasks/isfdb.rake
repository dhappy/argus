desc 'Import from the Internet Speculative Fiction Database'
namespace :isfdb do
  DB = Sequel.connect('mysql2://localhost/isfdb')

  def workFor(title:, creators:, legalname: nil, isMovie: false, copyright: nil, type: nil)
    creators = Nokogiri::HTML.parse(creators).text
    creators, altName = creators.split('^') if creators.include?('^')
    creators = creators.split('+').join(' & ') # when saved as an array the uniqeness constraint doesn't work
    creators = Creators.find_or_create_by(name: creators)
    creators.aliases = [] unless creators.aliases
    creators.aliases = (JSON.parse(creators.aliases)).push(altName).uniq if altName
    creators.legalname = legalname if legalname
    creators.save
    (
      if isMovie
        creators.movies.find_or_create_by(title: title)
      else
        creators.books.find_or_create_by(title: title)
      end
    )
    .tap do |work|
      work.creators = creators
      work.copyright ||= copyright
      work.types = [] unless work.types
      work.types = (JSON.parse(work.types)).push(type).uniq if type
      work.save
    end
  end

  # Guarantee this is a valid Unix path
  def fname(str)
    if(str =~ /\// || str =~ /%2f/i) # contains / or %2F, so decode anything containing %2F
      str = str.gsub('%', '%25').gsub('/', '%2F').gsub("\x00", '%00')
    end
    str.mb_chars.limit(254).to_s # this causes compatability issues
  end

  desc 'Import award winners and nominees'
  task(awards: :environment) do |t, args|
    LEVELS = {
      '71': 'No Winner -- Insufficient Votes',
      '72': 'Not on ballot -- Insufficient Nominations',
      '73': 'No Award Given This Year',
      '81': 'Withdrawn',
      '82': 'Withdrawn -- Nomination Declined',
      '83': 'Withdrawn -- Conflict of Interest',
      '84': 'Withdrawn -- Official Publication in a Previous Year',
      '85': 'Withdrawn -- Ineligible',
      '90': 'Finalists',
      '91': 'Made First Ballot',
      '92': "Preliminary Nominees",
      '93': 'Honorable Mentions',
      '98': 'Early Submissions',
      '99': 'Nominations Below Cutoff',
    }

    types = DB[
      'SELECT DISTINCT' \
      + ' award_type_id AS id,' \
      + ' award_type_short_name AS shortname,' \
      + ' award_type_name AS name' \
      + ' FROM award_types' \
      # + ' WHERE award_type_name = "Hugo Award"' \
    ]
    types.each do |type|
      award = Award.merge(
        title: Nokogiri::HTML.parse(type[:name]).text,
        shortname: Nokogiri::HTML.parse(type[:shortname]).text,
      )
      puts "#{Time.now.iso8601}: Award: #{award.shortname}"

      # The awards table duplicates both the title and author columns, so
      # there's no simple way to get the canonical_author record.
      #
      # I can't figure out how to disable casting in sequel
      # entries = DB[
      client = Mysql2::Client.new(host: 'localhost', database: 'isfdb')
      entries = client.query((
          'SELECT' \
          + ' award_title AS title,' \
          + ' award_author AS author,' \
          + ' award_cat_name AS cat,' \
          + ' award_year AS year,' \
          + ' award_movie AS movie,' \
          + ' title_ttype AS ttype,' \
          + ' title_copyright AS cpdate,' \
          + ' award_level as level' \
          + ' FROM awards' \
          + ' INNER JOIN award_cats ON awards.award_cat_id = award_cats.award_cat_id' \
          + ' INNER JOIN titles ON title_title = award_title' \
          + " WHERE award_type_id = #{type[:id]}" \
          + " AND title_ttype IN ('ANTHOLOGY','COLLECTION','NOVEL','NONFICTION','OMNIBUS','POEM','SHORTFICTION','CHAPBOOK')" \
        ),
        symbolize_keys: true,
        cast: false
      )
      entries.each_with_index do |entry, idx|
        next if Series.find_by(isfdbID: entry[:sid])
        next if entry[:title] == 'untitled' # an artist or editor award
        work = workFor(
          title: entry[:title], creators: entry[:author],  type: entry[:ttype],
          isMovie: entry[:movie].present?, copyright: entry[:cpdate],
        )
        year = award.years.find_or_create_by(
          number: entry[:year].sub(/-.*/, '')
        )
        category = year.categories.find_or_create_by(
          title: Nokogiri::HTML.parse(entry[:cat]).text
        )

        if work.nominations.include?(category)
          puts "  #{Time.now.iso8601}: #{idx}/#{entries.count}: Skipping: #{award.title}: #{year.number}: #{work}"
        else
          puts "  #{Time.now.iso8601}: #{idx}/#{entries.count}:  Linking: #{award.title}: #{year.number}: #{work}"
          Nominated.create(
            from_node: category, to_node: work, result: entry[:level]
          )
        end
      end
    end
  end

  desc 'Import information about series'
  task(series: :environment) do |t, args|
    # LIMIT = 500

    pubs = DB[
      'SELECT DISTINCT' \
      + ' series.series_id AS sid,' \
      + ' series_title AS series,' \
      + ' title_title AS title,' \
      + ' title_ttype AS ttype,' \
      + ' title_copyright AS cpdate,' \
      + ' title_seriesnum as snum,' \
      + ' title_seriesnum_2 as snum2,' \
      + ' author_legalname AS legal,' \
      + ' author_canonical AS author' \
      + ' FROM series' \
      + ' INNER JOIN titles ON titles.series_id = series.series_id' \
      + ' INNER JOIN canonical_author ON titles.title_id = canonical_author.title_id' \
      + ' INNER JOIN authors ON canonical_author.author_id = authors.author_id' \
      + ' AND series_parent IS NULL' \
      + " AND title_ttype IN ('ANTHOLOGY','COLLECTION','NOVEL','NONFICTION','OMNIBUS','POEM','SHORTFICTION','CHAPBOOK')" \
      + (defined?(LIMIT) ? " LIMIT #{LIMIT}" : '') \
    ]
    puts "Serializing Tree #{pubs.count} #{'Root'.pluralize(pubs.count)}"
    pubs.each_with_index do |pub, idx|
      next if Series.find_by(isfdbID: pub[:sid])
      next if pub[:title] == 'untitled' # an artist or editor award
      work = workFor(
        title: pub[:title], creators: pub[:author], isMovie: pub[:movie],
        copyright: pub[:cpdate], type: pub[:ttype]
      )
      series = Series.find_or_create_by(
        title: Nokogiri::HTML.parse(pub[:series]).text, isfdbID: pub[:sid]
      )
      rank = "#{pub[:snum]}#{pub[:snum2] ? ".#{pub[:snum2]}" : ''}"
      if work.series.include?(series)
        puts "  #{idx}/#{pubs.count}:Skipping:#{rank}: #{series.title}: #{work.copyright}: #{work}"
      else
        puts "   #{idx}/#{pubs.count}:Linking:#{rank}: #{series.title}: #{work.copyright}: #{work}"
        Contains.create(from_node: series, to_node: work, rank: rank)
      end
    end

    puts 'Getting direct children of roots'
    sids = DB[ # nodes with parents just imported
      'SELECT DISTINCT' \
      + ' posts.series_id AS id' \
      + ' FROM series AS pres, series AS posts' \
      + ' WHERE pres.series_parent IS NULL' \
      + ' AND pres.series_id = posts.series_parent' \
    ]
    sids = sids.map{ |row| row[:id] }
    puts "Got Serial IDs  of Children: #{sids.count} #{'ID'.pluralize(sids.count)}"
    pubs = DB[ # first level of children
      'SELECT DISTINCT' \
      + ' series.series_id AS sid,' \
      + ' series_title AS series,' \
      + ' title_title AS title,' \
      + ' title_ttype AS ttype,' \
      + ' title_copyright AS cpdate,' \
      + ' title_seriesnum as snum,' \
      + ' title_seriesnum_2 as snum2,' \
      + ' series_parent AS parent,' \
      + ' series_parent_position AS pos,' \
      + ' author_canonical AS author' \
      + ' FROM series, titles, canonical_author, authors' \
      + ' WHERE titles.series_id=series.series_id' \
      + ' AND titles.title_id=canonical_author.title_id' \
      + ' AND canonical_author.author_id=authors.author_id' \
      + " AND series.series_id IN (#{sids.join(?,)})" \
      + " AND title_ttype IN ('ANTHOLOGY','COLLECTION','NOVEL','NONFICTION','OMNIBUS','POEM','SHORTFICTION','CHAPBOOK')" \
      + ' ORDER BY series_parent' \
      + (defined?(LIMIT) ? " LIMIT #{LIMIT}" : '') \
    ]
    pubs.each_with_index do |pub, idx|
      next if pub[:title] == 'untitled' # an artist or editor award
      work = workFor(
        title: pub[:title], creators: pub[:author], isMovie: pub[:movie],
        copyright: pub[:cpdate], type: pub[:ttype]
      )
      parent = Series.find_by(isfdbID: pub[:parent])
      raise RuntimeError, "Missing Parent: #{pub[:parent]}" unless parent
      series = Series.find_or_create_by(
        title: Nokogiri::HTML.parse(pub[:series]).text, isfdbID: pub[:sid]
      )
      if work.series.include?(series)
        puts "  #{idx}/#{pubs.count}:Skipping: #{parent.title} — #{series.title}: #{work.copyright}: #{work}"
      else
        puts "   #{idx}/#{pubs.count}:Linking: #{parent.title} — #{series.title}: #{work.copyright}: #{work}"
        unless parent.series.include?(series)
          Contains.create(from_node: parent, to_node: series, rank: pub[:pos])
        end
        Contains.create(from_node: series, to_node: work, rank: pub[:snum])
      end
    end
  end

  desc 'Import information about cover images and isbns'
  task(covers: :environment) do |t, args|
    pubs = DB[
      'SELECT DISTINCT' \
      + ' pub_title AS title,' \
      + ' author_canonical AS author,' \
      + ' author_legalname AS legal,' \
      + ' pub_isbn AS isbn,' \
      + ' pub_frontimage AS image' \
      + ' FROM pubs' \
      + ' JOIN pub_authors ON pubs.pub_id = pub_authors.pub_id' \
      + ' JOIN authors ON pub_authors.author_id = authors.author_id' \
    ]
    pubs.each do |pub|
      next if pub[:title] == 'untitled' # an artist or editor award
      book = workFor(
        title: pub[:title], creators: pub[:author], legalname: pub[:legal],
        copyright: pub[:cpdate], type: pub[:ttype],
      )

      if pub[:isbn].present?
        version = book.versions.find_or_create_by(isbn: pub[:isbn])
        pat = "../book/by/#{fname(book.creators.name)}/#{fname(book.title)}/covers/#{pub[:isbn]}.*"
        puts "Globbing: #{pat}"
        if (glob = Dir.glob(pat)).any?
          cid = nil
          IO.popen(['ipfs', 'add', glob.first], 'r+') do |cmd|
            out = cmd.readlines.last
            cid = out&.split.try(:[], 1)
            unless $?.success? && cid
              puts "Error: IPFS Import of #{glob.first})"
              next
            end
          end
          meta = nil
          IO.popen(['exiftool', '-s', '-ImageWidth', '-ImageHeight', '-Mimetype', glob.first], 'r+') do |cmd|
            meta = cmd.readlines.reduce({}) do |size, line|
              if match = /^(?<prop>[^:]+\S)\s+:\s+(?<val>\S.+)\r?\n?$/.match(line)
                prop = match[:prop].sub(/^Image/, '').downcase
                size[prop.to_sym] = match[:val]
              end
              size
            end
            unless $?.success?
              puts "Error: EXIF Metadata of #{glob.first})"
              next
            end
          end
          mimetype = meta[:mimetype] || "image/#{glob.first.split('.').slice(-1)[0]}" # often wrong, but rarely ambiguous
          puts "  Got Size: #{meta[:width]}✕#{meta[:height]} (#{cid})"
          
          version.cover = Cover.find_or_create_by(
            cid: cid, width: meta[:width], height: meta[:height], mimetype: mimetype
          ) 
        elsif pub[:image].present?
          version.cover = Cover.find_or_create_by(url: pub[:image])
        end
      end
    end
  end
end