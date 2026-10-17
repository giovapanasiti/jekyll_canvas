# frozen_string_literal: true

module JekyllCanvas
  # Polls the source tree once a second; a change that the API did not cause triggers a rebuild.
  # Files the API writes are announced with `ignore` (before) and `acknowledge` (after), so the
  # engine's own writes never rebuild twice while a later external edit of the same file still does.
  class Watcher
    ALWAYS_SKIP = %w[_site .git .jekyll-cache .sass-cache node_modules vendor .bundle].freeze
    MARKER_TTL = 10.0

    def initialize(root:, builder:, interval: 1.0, debounce: 0.3)
      @root = File.realpath(root)
      @builder = builder
      @interval = interval
      @debounce = debounce
      @markers = {}
      @lock = Mutex.new
      @snapshot = nil
      @stop = false
    end

    # The engine is about to write `path`.
    def ignore(path)
      @lock.synchronize { @markers[File.expand_path(path)] = now }
    end

    # The engine has written (or deleted) `path`: remember its current state as the baseline.
    def acknowledge(path)
      path = File.expand_path(path)
      @lock.synchronize do
        @markers.delete(path)
        next unless @snapshot

        stat = (File.lstat(path) if File.exist?(path))
        stat&.file? ? @snapshot[path] = [stat.mtime.to_f, stat.size] : @snapshot.delete(path)
      end
    end

    # Takes the baseline that later ticks are compared with.
    def snapshot!
      @lock.synchronize { @snapshot = scan }
    end

    def start
      snapshot!
      @thread = Thread.new do
        Thread.current.report_on_exception = false
        until @stop
          sleep @interval
          tick
        end
      end
    end

    def stop
      @stop = true
      @thread&.kill
    end

    # One polling step (public for tests). Returns true when a rebuild was triggered.
    def tick
      snapshot! if @snapshot.nil?
      changed = @lock.synchronize do
        current = scan
        diff = (current.keys | @snapshot.keys).select { |p| current[p] != @snapshot[p] }
        @snapshot = current
        @markers.delete_if { |_, t| now - t > MARKER_TTL }
        diff.reject { |p| @markers.key?(p) }
      end
      return false if changed.empty?

      sleep @debounce
      snapshot!
      @builder.build
      true
    rescue StandardError => e
      warn "[jekyll-canvas] watcher: #{e.class}: #{e.message}"
      false
    end

    private

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def scan
      out = {}
      walk(@root, out)
      out
    end

    def walk(dir, out)
      Dir.children(dir).each do |name|
        next if name.start_with?(".") && !included?(name)
        next if ALWAYS_SKIP.include?(name) || name.end_with?("~")

        path = File.join(dir, name)
        rel = path.delete_prefix("#{@root}/")
        next if excluded?(rel) || path.start_with?(@builder.cache_dir)

        stat = File.lstat(path)
        if stat.directory? then walk(path, out)
        elsif stat.file? then out[path] = [stat.mtime.to_f, stat.size]
        end
      end
    rescue SystemCallError
      nil
    end

    def included?(name)
      Array(@builder.info[:include]).include?(name)
    end

    def excluded?(rel)
      Array(@builder.info[:exclude]).any? do |entry|
        entry = entry.to_s.chomp("/")
        rel == entry || rel.start_with?("#{entry}/") || File.fnmatch?(entry, rel, File::FNM_PATHNAME | File::FNM_EXTGLOB)
      end
    end
  end
end
