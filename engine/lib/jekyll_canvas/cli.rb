# frozen_string_literal: true

require "optparse"
require "digest"
require "fileutils"

module JekyllCanvas
  # Command line entry point: parse options, build once, serve, print the ready line.
  module CLI
    module_function

    def parse(argv)
      opts = { site: Dir.pwd, port: 0, cache_dir: nil, open: false }
      OptionParser.new do |o|
        o.banner = "Usage: jekyll-canvas-server [--site PATH] [--port N] [--cache-dir PATH] [--open]"
        o.on("--site PATH", "Jekyll site folder (default: current directory)") { |v| opts[:site] = v }
        o.on("--port N", Integer, "Port to listen on (default: random)") { |v| opts[:port] = v }
        o.on("--cache-dir PATH", "Where the built site is kept") { |v| opts[:cache_dir] = v }
        o.on("--open", "Open the editor in the default browser when ready") { opts[:open] = true }
      end.parse!(argv)
      opts
    end

    def darwin?
      RUBY_PLATFORM.match?(/darwin/)
    end

    def default_cache_dir(root)
      hash = Digest::SHA1.hexdigest(File.realpath(root))[0, 12]
      return File.join(Dir.home, "Library", "Caches", "JekyllCanvas", hash) if darwin?

      xdg = ENV["XDG_CACHE_HOME"].to_s
      base = xdg.empty? ? File.join(Dir.home, ".cache") : xdg
      File.join(base, "jekyll-canvas", hash)
    end

    def open_command
      darwin? ? "open" : "xdg-open"
    end

    def run(argv)
      Encoding.default_external = Encoding::UTF_8
      Encoding.default_internal = nil
      real_stdout = $stdout
      $stdout = $stderr # Jekyll and plugins log to $stdout; only the ready line may use the real one
      opts = parse(argv)
      root = File.realpath(File.expand_path(opts[:site]))
      abort "jekyll-canvas: #{root} is not a directory" unless File.directory?(root)
      Dir.chdir(root)
      load_jekyll_plugins

      require "jekyll_canvas"
      cache_dir = File.expand_path(opts[:cache_dir] || default_cache_dir(root))
      builder = Builder.new(root: root, cache_dir: cache_dir)
      watcher = Watcher.new(root: root, builder: builder)
      public_dir = File.expand_path("../../public", __dir__)
      server = Server.new(root: root, builder: builder, watcher: watcher, public_dir: public_dir, port: opts[:port])

      stopping = false
      stop = proc do |_signal|
        next if stopping

        stopping = true
        Thread.new do
          watcher.stop
          server.shutdown
        end
      end
      trap("INT", &stop)
      trap("TERM", &stop)

      server_thread = server.start_in_background
      warn "[jekyll-canvas] building #{root} ..."
      builder.build
      warn "[jekyll-canvas] ready (#{builder.last_build_ms} ms)#{builder.error ? ", build error: #{builder.error}" : ''}"
      real_stdout.puts "JEKYLL_CANVAS_READY #{server.url}"
      real_stdout.flush
      watcher.start
      watch_parent_stdin(stop) if ENV["JC_EXIT_ON_STDIN_EOF"] == "1"
      system(open_command, server.url) if opts[:open]
      server_thread.join
      0
    end

    # The desktop app holds our stdin open; EOF means it died without stopping us.
    def watch_parent_stdin(stop)
      Thread.new do
        $stdin.read
        stop.call(nil)
      rescue IOError
        stop.call(nil)
      end
    end

    def load_jekyll_plugins
      require "jekyll"
      Jekyll::PluginManager.require_from_bundler
    rescue LoadError, StandardError => e
      warn "[jekyll-canvas] could not load bundled Jekyll plugins: #{e.class}: #{e.message}"
    end
  end
end
