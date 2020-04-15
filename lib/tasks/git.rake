namespace :git do
  desc 'Spider [dir], find git repositories, & run a git command: [cmd]'
  task(:cmd, [:cmd, :dir] => [:environment]) do |t, args|
    cmd = args[:cmd].split(' ')

    run = ->(dir) {
      puts "Running git #{cmd.join(' ')} in #{dir}"
      FileUtils.chdir(dir) do
        system(*(%w[git] + cmd))
      end
    }

    spider = ->(dir) {
      Dir.glob("#{dir}/*").each do |sub|
        if File.directory?(sub)
          isGit = /\/.git$/.match?(sub)
          puts "Check #{sub} #{isGit}"
          isGit ? run.call(dir) : spider.call(sub)
        end
      end
    }

    dir = args[:dir] || '../.../book'
    spider.call(dir)
  end

  desc 'Spider [dir], find git repositories, & commit with [msg]'
  task(:commit, [:msg, :dir] => [:environment]) do |t, args|
  end
end