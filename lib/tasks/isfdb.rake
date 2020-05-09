desc 'Import from the Internet Speculative Fiction Database'
namespace :isfdb do
  DB = Sequel.connect('mysql2://localhost/isfdb')

  def workFor(title:, creator:, legalName: nil, isMovie: false, copyright: nil, type: nil)
    creator = Nokogiri::HTML.parse(creator).text
    creator, altName = creator.split('^') if creator.include?('^')
    creators = creator.split('+').join(' & ') # when saved as an array the uniqeness constraint doesn't work
    creators = Creators.find_or_create_by(name: creators)
    creators.aliases = [] unless creators.aliases
    creators.aliases = (JSON.parse(creators.aliases)).push(pseudonym).uniq
    creators.legalName = legalName if legalName
    creators.save
    (
      if isMovie
        creators.movies.find_or_create_by(title: title)
      else
        creators.books.find_or_create_by(title: title)
      end
    )
    .tap do |work|
      work.copyright ||= copyright
      work.types = [] unless work.types
      work.types = (JSON.parse(work.types)).push(type).uniq
      work.save
    end
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
      puts "Award: #{award.shortname}"

      # The awards table duplicates both the title and author columns, so
      # there's no simple way to get the canonical_author record.
      entries = DB[
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
        + " WHERE award_type_id = ?" \
        + " AND title_ttype IN ('ANTHOLOGY','COLLECTION','NOVEL','NONFICTION','OMNIBUS','POEM','SHORTFICTION','CHAPBOOK')" \
        , type[:id]
      ]
      entries.each_with_index do |entry, idx|
        next if Series.find_by(isfdbID: pub[:sid])
        next if pub[:title] == 'untitled' # an artist or editor award
        work = workFor(
          title: pub[:title], creator: pub[:creator],  type: pub[:ttype],
          isMovie: pub[:movie].present?, copyright: pub[:cpdate],
        )
        year = award.years.find_or_create_by(
          number: entry[:year].sub(/-.*/, '')
        )
        category = year.categories.find_or_create_by(
          title: Nokogiri::HTML.parse(entry[:cat]).text
        )

        if art.nominations.include?(category)
          puts "  #{idx}/#{entries.count}: Skipping: #{award.title}: #{year.number}: #{work}"
        else
          puts "   #{idx}/#{entries.count}: Linking: #{award.title}: #{year.number}: #{work}"
          Nomination.create(
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
      + ' creator_legalname AS legal,' \
      + ' creator_canonical AS creator' \
      + ' FROM series' \
      + ' INNER JOIN titles ON titles.series_id = series.series_id' \
      + ' INNER JOIN canonical_creator ON titles.title_id = canonical_creator.title_id' \
      + ' INNER JOIN creators ON canonical_creator.creator_id = creators.creator_id' \
      + ' AND series_parent IS NULL' \
      + " AND title_ttype IN ('ANTHOLOGY','COLLECTION','NOVEL','NONFICTION','OMNIBUS','POEM','SHORTFICTION','CHAPBOOK')" \
      + (defined?(LIMIT) ? " LIMIT #{LIMIT}" : '') \
    ]
    puts "Serializing Tree #{pubs.count} #{'Root'.pluralize(pubs.count)}"
    pubs.each_with_index do |pub, idx|
      next if Series.find_by(isfdbID: pub[:sid])
      next if pub[:title] == 'untitled' # an artist or editor award
      work = workFor(
        title: pub[:title], creator: pub[:creator], isMovie: pub[:movie],
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
      + ' creator_canonical AS creator' \
      + ' FROM series, titles, canonical_creator, creators' \
      + ' WHERE titles.series_id=series.series_id' \
      + ' AND titles.title_id=canonical_creator.title_id' \
      + ' AND canonical_creator.creator_id=creators.creator_id' \
      + " AND series.series_id IN (#{sids.join(?,)})" \
      + " AND title_ttype IN ('ANTHOLOGY','COLLECTION','NOVEL','NONFICTION','OMNIBUS','POEM','SHORTFICTION','CHAPBOOK')" \
      + ' ORDER BY series_parent' \
      + (defined?(LIMIT) ? " LIMIT #{LIMIT}" : '') \
    ]
    pubs.each_with_index do |pub, idx|
      next if pub[:title] == 'untitled' # an artist or editor award
      work = workFor(
        title: pub[:title], creator: pub[:creator], isMovie: pub[:movie],
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
      + ' creator_canonical AS creator,' \
      + ' pub_isbn AS isbn,' \
      + ' pub_frontimage AS image' \
      + ' FROM pubs' \
      + ' JOIN pub_creators ON pubs.pub_id = pub_creators.pub_id' \
      + ' JOIN creators ON pub_creators.creator_id = creators.creator_id',
    ]
    pubs.each do |pub|
      next if pub[:title] == 'untitled' # an artist or editor award
      art = workFor(
        title: pub[:title], creator: pub[:creator], isMovie: pub[:movie],
        copyright: pub[:cpdate], type: pub[:ttype]
      )

      if pub[:isbn].present?
        version = book.versions.find_or_create_by(isbn: pub[:isbn])
        if pub[:image].present?
          version.cover = Cover.find_or_create_by(url: pub[:image])
        end
      end
    end
  end
end