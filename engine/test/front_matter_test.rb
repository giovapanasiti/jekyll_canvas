# frozen_string_literal: true

require "test_helper"
require "jekyll_canvas/front_matter"

class FrontMatterTest < Minitest::Test
  FM = JekyllCanvas::FrontMatter

  def test_split
    content = "---\ntitle: Hi\nlang: it\n---\n\nBody line\nsecond\n"
    parts = FM.split(content)
    assert_equal "title: Hi\nlang: it\n", parts.raw
    assert_equal "Body line\nsecond\n", parts.body
    assert_equal 6, parts.body_start_line
    assert_equal "title: Hi\nlang: it\n", content[parts.yaml_start...parts.yaml_end]
    assert_equal parts.body, content[parts.body_start..]
  end

  def test_body_start_line_matches_file_line
    content = "---\na: 1\n---\nFirst\nSecond\n"
    parts = FM.split(content)
    assert_equal 4, parts.body_start_line
    assert_equal "Second", content.lines[parts.body_start_line].chomp
  end

  def test_no_front_matter
    parts = FM.split("<h1>Hi</h1>\n")
    assert_nil parts.raw
    assert_equal 1, parts.body_start_line
    assert_equal "<h1>Hi</h1>\n", parts.body
    refute parts.front_matter?
  end

  def test_empty_front_matter_and_dots_terminator
    parts = FM.split("---\n---\nBody\n")
    assert_equal "", parts.raw
    assert_equal "Body\n", parts.body
    parts = FM.split("---\na: 1\n...\nBody\n")
    assert_equal "a: 1\n", parts.raw
  end

  def test_crlf_and_unicode_offsets
    content = "---\r\ntitle: Perché \u{1F600}\r\n---\r\nCorpo\r\n"
    parts = FM.split(content)
    assert_equal "title: Perché \u{1F600}\r\n", content[parts.yaml_start...parts.yaml_end]
    assert_equal "Corpo\r\n", parts.body
  end

  def test_load_hash
    assert_equal({ "a" => 1 }, FM.load_hash("a: 1\n"))
    assert_equal({}, FM.load_hash(""))
    assert_nil FM.load_hash(nil)
    assert_nil FM.load_hash("- a\n- b\n")
    assert_nil FM.load_hash("a: [\n")
    assert_kind_of Date, FM.load_hash("d: 2026-10-17\n")["d"]
  end
end
