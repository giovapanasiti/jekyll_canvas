# frozen_string_literal: true

require "test_helper"
require "jekyll_canvas/cli"

class CliTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir
    @hash = Digest::SHA1.hexdigest(File.realpath(@root))[0, 12]
    @old_xdg = ENV["XDG_CACHE_HOME"]
  end

  def teardown
    FileUtils.remove_entry(@root)
    ENV["XDG_CACHE_HOME"] = @old_xdg
    JekyllCanvas::CLI.singleton_class.send(:remove_method, :darwin?) if JekyllCanvas::CLI.singleton_class.method_defined?(:darwin?, false)
  end

  def stub_platform(value)
    JekyllCanvas::CLI.define_singleton_method(:darwin?) { value }
  end

  def test_macos_cache_dir
    stub_platform(true)
    assert_equal File.join(Dir.home, "Library", "Caches", "JekyllCanvas", @hash), JekyllCanvas::CLI.default_cache_dir(@root)
    assert_equal "open", JekyllCanvas::CLI.open_command
  end

  def test_linux_cache_dir_uses_xdg_cache_home
    stub_platform(false)
    ENV["XDG_CACHE_HOME"] = "/tmp/xdg-cache"
    assert_equal File.join("/tmp/xdg-cache", "jekyll-canvas", @hash), JekyllCanvas::CLI.default_cache_dir(@root)
    assert_equal "xdg-open", JekyllCanvas::CLI.open_command
  end

  def test_linux_cache_dir_falls_back_to_dot_cache
    stub_platform(false)
    ENV.delete("XDG_CACHE_HOME")
    assert_equal File.join(Dir.home, ".cache", "jekyll-canvas", @hash), JekyllCanvas::CLI.default_cache_dir(@root)
  end
end
