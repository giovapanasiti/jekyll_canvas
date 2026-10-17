# frozen_string_literal: true

require "open3"
require_relative "errors"

module JekyllCanvas
  # Thin wrapper over the git CLI (always argument arrays, never a shell string).
  class Git
    def initialize(root)
      @root = root
    end

    def repo?
      out, status = run("rev-parse", "--is-inside-work-tree", check: false)
      status.success? && out.strip == "true"
    end

    def status
      return { git: false } unless repo?

      branch, ok = run("symbolic-ref", "--short", "-q", "HEAD", check: false).then { |o, s| [o.strip, s.success?] }
      branch = run("rev-parse", "--short", "HEAD", check: false).first.strip unless ok && !branch.empty?
      { git: true, branch: branch, files: changed_files }
    end

    def changed_files
      out, = run("status", "--porcelain=v1", "-z", "--untracked-files=all")
      entries = out.split("\0")
      files = []
      until entries.empty?
        entry = entries.shift
        next if entry.length < 4

        xy = entry[0, 2]
        path = entry[3..]
        entries.shift if xy.include?("R") || xy.include?("C") # the original path follows
        files << { path: path, status: collapse(xy) }
      end
      files
    end

    def diff(file)
      if tracked?(file)
        out, status = run("diff", "HEAD", "--", file, check: false)
        out, = run("diff", "--", file) unless status.success?
      else
        out, = run("diff", "--no-index", "--", "/dev/null", file, check: false)
      end
      out.to_s
    end

    def discard(file, abs_path)
      if in_head?(file)
        run("restore", "--source=HEAD", "--staged", "--worktree", "--", file)
      else
        run("rm", "--cached", "-q", "--", file, check: false) if tracked?(file)
        File.delete(abs_path) if File.exist?(abs_path)
      end
    end

    def commit(message, files)
      raise ApiError.new("invalid", "commit message is required") if message.to_s.strip.empty?

      files = changed_files.map { |f| f[:path] } if files.nil? || files.empty?
      raise ApiError.new("git_failed", "nothing to commit") if files.empty?

      run("add", "--", *files)
      run("commit", "-m", message, "--", *files)
      run("rev-parse", "--short", "HEAD").first.strip
    end

    private

    def collapse(xy)
      return "??" if xy == "??"

      x, y = xy.chars
      code = y == " " ? x : y
      { "M" => "M", "A" => "A", "D" => "D", "R" => "R", "C" => "A" }.fetch(code, "M")
    end

    def tracked?(file)
      run("ls-files", "--error-unmatch", "--", file, check: false).last.success?
    end

    def in_head?(file)
      run("cat-file", "-e", "HEAD:#{file}", check: false).last.success?
    end

    def run(*args, check: true)
      out, err, status = Open3.capture3("git", "-C", @root, *args)
      if check && !status.success?
        raise ApiError.new("git_failed", (err.to_s.strip.empty? ? out : err).to_s.strip)
      end
      [out, status]
    rescue Errno::ENOENT
      raise ApiError.new("git_failed", "git is not installed")
    end
  end
end
