namespace :argus do

  desc 'Insert images into IPFS'
  task(images: :environment) do |t, args|
    require 'net/http'
    require 'ipfs/client'

    q = Content.as(:c).where(
      'c.ipfs_id IS NULL AND c.url IS NOT NULL'
    )
    q.each do |c|
      print "Processing #{c.url}"
      next unless c.url.present?
      if /^http:\/\/www.isfdb.org\/wiki\/images\/(.+)$/ =~ c.url
        filename = "#{Rails.root}/../.../guten-images/#{$1}"
        print "\n  Checking: #{filename}"
        unless File.exists?(filename)
          puts ': Skipping While Downloading…'
        else
          cover = IPFS::Client.default.add(filename)
          ext = c.url.split('.').pop
          ext = :jpeg if ext == 'jpg'
          c.update({
            mimetype: "image/#{ext}", ipfs_id: cover.hashcode,
          })
        end
      else
        res = Net::HTTP.get(URI.parse(c.url.split('|').first))
        Tempfile.open(
          'cover', "#{Rails.root}/tmp", encoding: 'ascii-8bit'
        ) do |file|
          file.write(res)
          cover = IPFS::Client.default.add(file.path)
          ext = c.url.split('.').pop
          ext = :jpeg if ext == 'jpg'
          c.update({
            mimetype: "image/#{ext}", ipfs_id: cover.hashcode,
          })
        end
      end
      puts " to #{c.ipfs_id} (#{c.mimetype})" if c.ipfs_id
    end
  end

  desc 'Heal'
  task(heal: :environment) do |t, args|

  end
end