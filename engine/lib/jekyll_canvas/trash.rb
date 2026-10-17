# frozen_string_literal: true

require "fileutils"
require "open3"
require "time"
require_relative "errors"

module JekyllCanvas
  # Moves a file to the system Trash (macOS ~/.Trash, freedesktop.org Trash elsewhere).
  # It never deletes permanently: if trashing fails an ApiError is raised and the file stays put.
  # Platform and base directories are injectable so tests never touch the real Trash.
  class Trash
    # `gio:` is true (use `gio trash` when it is on PATH), false (never) or a path to the binary.
    def initialize(platform: RUBY_PLATFORM, home: Dir.home, mac_trash: nil, xdg_data_home: ENV["XDG_DATA_HOME"], gio: true, clock: -> { Time.now })
      @mac = platform.to_s.match?(/darwin/)
      @mac_trash = mac_trash || File.join(home, ".Trash")
      data_home = xdg_data_home.to_s.empty? ? File.join(home, ".local", "share") : xdg_data_home
      @linux_trash = File.join(data_home, "Trash")
      @gio = gio
      @clock = clock
    end

    # Returns where the file ended up.
    def trash(abs)
      raise ApiError.new("not_found", "file not found") unless File.exist?(abs) || File.symlink?(abs)

      @mac ? trash_mac(abs) : trash_linux(abs)
    rescue SystemCallError => e
      raise ApiError.new("invalid", "impossibile spostare il file nel Cestino (#{e.message}); il file non è stato toccato")
    end

    private

    def trash_mac(abs)
      FileUtils.mkdir_p(@mac_trash)
      target = unique_mac_path(File.basename(abs))
      FileUtils.mv(abs, target)
      target
    end

    def unique_mac_path(name)
      path = File.join(@mac_trash, name)
      return path unless taken?(path)

      ext = File.extname(name)
      stem = File.basename(name, ext)
      stamp = @clock.call.strftime("%H.%M.%S")
      candidate = File.join(@mac_trash, "#{stem} #{stamp}#{ext}")
      n = 1
      while taken?(candidate)
        n += 1
        candidate = File.join(@mac_trash, "#{stem} #{stamp}-#{n}#{ext}")
      end
      candidate
    end

    def trash_linux(abs)
      gio = gio_binary
      return trash_with_gio(gio, abs) if gio

      trash_freedesktop(abs)
    end

    def gio_binary
      return nil if @gio == false || @gio.nil?
      return (File.executable?(@gio) ? @gio : nil) if @gio.is_a?(String)

      ENV["PATH"].to_s.split(File::PATH_SEPARATOR).map { |dir| File.join(dir, "gio") }.find { |p| File.file?(p) && File.executable?(p) }
    end

    def trash_with_gio(gio, abs)
      out, status = Open3.capture2e(gio, "trash", abs)
      unless status.success?
        raise ApiError.new("invalid", "impossibile spostare il file nel Cestino (gio: #{out.strip}); il file non è stato toccato")
      end

      "trash:///#{File.basename(abs)}"
    rescue Errno::ENOENT
      trash_freedesktop(abs)
    end

    # https://specifications.freedesktop.org/trash-spec/ - home trash with a .trashinfo written first.
    def trash_freedesktop(abs)
      files = File.join(@linux_trash, "files")
      infos = File.join(@linux_trash, "info")
      FileUtils.mkdir_p([files, infos], mode: 0o700)
      name, info_path = reserve_info(File.basename(abs), files, infos, abs)
      target = File.join(files, name)
      begin
        FileUtils.mv(abs, target)
      rescue SystemCallError
        File.delete(info_path) if File.exist?(info_path)
        raise
      end
      target
    end

    # Creates `info/<name>.trashinfo` exclusively so the chosen name is ours.
    def reserve_info(base, files, infos, abs)
      ext = File.extname(base)
      stem = File.basename(base, ext)
      n = 0
      loop do
        name = n.zero? ? base : "#{stem}.#{n}#{ext}"
        n += 1
        next if taken?(File.join(files, name))

        info_path = File.join(infos, "#{name}.trashinfo")
        begin
          File.open(info_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |f| f.write(trashinfo(abs)) }
          return [name, info_path]
        rescue Errno::EEXIST
          next
        end
      end
    end

    def trashinfo(abs)
      "[Trash Info]\nPath=#{encode_path(abs)}\nDeletionDate=#{@clock.call.strftime('%Y-%m-%dT%H:%M:%S')}\n"
    end

    def encode_path(path)
      path.b.gsub(%r{[^A-Za-z0-9\-._~/]}n) { |c| format("%%%02X", c.ord) }
    end

    def taken?(path)
      File.exist?(path) || File.symlink?(path)
    end
  end
end
