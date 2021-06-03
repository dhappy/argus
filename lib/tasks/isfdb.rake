desc 'Import from the Internet Speculative Fiction Database'
namespace :isfdb do
  DB = Sequel.connect('mysql2://localhost/isfdb')

  def workFor(
    title:, creators:, legalname: nil, is_movie: false,
    published_at: nil, type: nil, copyright: nil, isfdbID: nil
  )
    creators = Nokogiri::HTML.parse(creators).text
    creators, altName = creators.split('^') if creators.include?('^')
    creators = creators.split('+').join(' & ') # when saved as an array the uniqeness constraint doesn't work
    creators = Creators.find_or_create_by(name: creators)
    creators.aliases = [] unless creators.aliases
    creators.aliases = (JSON.parse(creators.aliases)).push(altName).uniq if altName
    creators.legalname = legalname if legalname
    creators.save
    title = Nokogiri::HTML.parse(title).text
    (
      if is_movie
        creators.movies.find_or_create_by(title: title)
      elsif title
        creators.books.find_or_create_by(title: title)
      end
    )
    .tap do |work|
      work.creators = creators
      work.published_at ||= published_at
      work.types = [] unless work.types
      work.types = (JSON.parse(work.types)).push(type).uniq if type
      work.isfdbID = isfdbID if isfdbID
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
    TTYPES = \
      "'ANTHOLOGY','COLLECTION','NOVEL','NONFICTION'," \
      + "'OMNIBUS','POEM','SHORTFICTION','CHAPBOOK'"
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
        isfdbID: type[:id],
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
          + ' title_id AS tid,' \
          + ' title_parent AS parent,' \
          + ' title_ttype AS ttype,' \
          + ' title_copyright AS cpdate,' \
          + ' award_level AS level' \
          + ' FROM awards' \
          + ' INNER JOIN award_cats ON awards.award_cat_id = award_cats.award_cat_id' \
          + ' INNER JOIN titles ON title_title = award_title' \
          + " WHERE award_type_id = #{type[:id]}" \
          + " AND title_ttype IN (#{TTYPES})" \
        ),
        symbolize_keys: true,
        cast: false
      )
      entries.each_with_index do |entry, idx|
        if entry[:title] == 'untitled' # an artist or editor award
          puts "Skipping 'untitled' by #{entry[:author]}"
          next
        end
        entry[:tid] = entry[:tid].to_i
        entry[:parent] = entry[:parent].to_i
        work = workFor(
          title: entry[:title], creators: entry[:author],
          type: entry[:ttype], is_movie: entry[:movie].present?,
          copyright: entry[:cpdate],
          isfdbID: (entry[:parent] != 0 ? entry[:parent] : entry[:tid]),
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
      + ' titles.title_id AS tid,' \
      + ' title_parent AS parent,' \
      + ' series_title AS series,' \
      + ' title_title AS title,' \
      + ' title_ttype AS ttype,' \
      + ' title_copyright AS cpdate,' \
      + ' title_seriesnum as snum,' \
      + ' title_seriesnum_2 as snum2,' \
      + " GROUP_CONCAT(author_legalname SEPARATOR ' & ') AS legal," \
      + " GROUP_CONCAT(author_canonical SEPARATOR ' & ') AS author" \
      + ' FROM series' \
      + ' INNER JOIN titles ON titles.series_id = series.series_id' \
      + ' INNER JOIN canonical_author ON titles.title_id = canonical_author.title_id' \
      + ' INNER JOIN authors ON canonical_author.author_id = authors.author_id' \
      + ' AND series_parent IS NULL' \
      + " AND title_ttype IN ('ANTHOLOGY','COLLECTION','NOVEL','NONFICTION','OMNIBUS','POEM','SHORTFICTION','CHAPBOOK')" \
      + ' GROUP BY series.series_id, series_title, title_title,' \
      + ' title_ttype, title_copyright, title_seriesnum,' \
      + ' titles.title_id, title_seriesnum_2' \
      + (defined?(LIMIT) ? " LIMIT #{LIMIT}" : '') \
    ]
    puts "Serializing Tree #{pubs.count} #{'Root'.pluralize(pubs.count)}"
    pubs.each_with_index do |pub, idx|
      next if pub[:title] == 'untitled' # an artist or editor award
      pub[:tid] = pub[:tid].to_i
      pub[:parent] = pub[:parent].to_i
      work = workFor(
        title: pub[:title], creators: pub[:author], is_movie: pub[:movie],
        copyright: pub[:cpdate], type: pub[:ttype],
        isfdbID: (pub[:parent] != 0 ? pub[:parent] : pub[:tid]),
      )
      series = Series.find_or_create_by(
        title: Nokogiri::HTML.parse(pub[:series]).text, isfdbID: pub[:sid]
      )
      rank = "#{pub[:snum]}#{pub[:snum2] ? ".#{pub[:snum2]}" : ''}"
      if work.series.include?(series)
        puts "  #{idx}/#{pubs.count}:Skipping:#{rank}: #{series.title}: #{work}"
      else
        puts "   #{idx}/#{pubs.count}:Linking:#{rank}: #{series.title}: #{work}"
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
      + ' titles.title_id AS tid,' \
      + ' title_parent AS parent,' \
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
      pub[:tid] = pub[:tid].to_i
      pub[:parent] = pub[:parent].to_i
      work = workFor(
        title: pub[:title], creators: pub[:author], is_movie: pub[:movie],
        copyright: pub[:cpdate], type: pub[:ttype],
        isfdbID: (pub[:parent] != 0 ? pub[:parent] : pub[:tid]),
      )
      parent = Series.find_by(isfdbID: pub[:parent])
      unless parent
        puts "Error: Missing Parent: #{pub[:parent]}/#{pub[:sid]} (#{pub[:title]})"
        series = DB[
          'SELECT DISTINCT' \
          + ' series.series_id AS id,' \
          + ' series_title AS title' \
          + ' FROM series' \
          + " WHERE series.series_id = #{pub[:parent]}" \
        ]
        parent = Series.find_or_create_by(
          title: Nokogiri::HTML.parse(series[:title]).text, isfdbID: series[:id]
        )
        puts "  Created #{parent.title}"
      end
      series = Series.find_or_create_by(
        title: Nokogiri::HTML.parse(pub[:series]).text, isfdbID: pub[:sid]
      )
      if work.series.include?(series)
        puts "  #{idx}/#{pubs.count}:Skipping: #{parent.title} — #{series.title}: #{work}"
      else
        puts "   #{idx}/#{pubs.count}:Linking: #{parent.title} — #{series.title}: #{work}"
        unless parent.series.include?(series)
          Contains.create(from_node: parent, to_node: series, rank: pub[:pos])
        end
        Contains.create(from_node: series, to_node: work, rank: pub[:snum])
      end
    end
  end

  desc 'Import information about cover images and isbns'
  task(covers: :environment) do |t, args|
    require 'ipfs/client'

    pubs = DB[
      'SELECT DISTINCT' \
      + ' pub_title AS title,' \
      + ' author_canonical AS author,' \
      + ' author_legalname AS legal,' \
      + ' pub_year AS year,' \
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
        type: pub[:ttype]
      )
      puts "Cover for #{book.title}"

      if pub[:isbn].present?
        version = book.versions.find_or_create_by(isbn: pub[:isbn])
        version.update(published_at: pub[:year])

        if pub[:image].present?
          version.cover = Cover.find_or_create_by(url: pub[:image])
        end
      end
    end
  end
end