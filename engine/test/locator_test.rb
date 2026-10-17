# frozen_string_literal: true

require "test_helper"
require "jekyll_canvas/locator"

class LocatorTest < Minitest::Test
  Record = Struct.new(:file, :format, :layouts, :includes)

  def setup
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, "_layouts"))
    FileUtils.mkdir_p(File.join(@dir, "_includes"))
    File.write(File.join(@dir, "page.html"), <<~HTML)
      ---
      title: We are a small team
      ---
      <h1>Intro</h1>
      <p>We are a small team that loves Jekyll &amp; "Ruby" &#38; more.</p>
      <p>Two   words
      across lines</p>
      <p>{{ page.title }} dynamic</p>
      <p>Caf&eacute; &egrave; l&#39;ora &#x27;x&#x27; it's</p>
      <p>Homepage</p>
      <p>Home</p>
    HTML
    File.write(File.join(@dir, "_layouts/default.html"), "<footer>Hardcoded footer</footer>\n{{ 'Hardcoded footer' | upcase }}\n")
    File.write(File.join(@dir, "_includes/header.html"), "<p>Header words</p>\n")
    @record = Record.new("page.html", "html", ["_layouts/default.html"], ["_includes/header.html"])
    @locator = JekyllCanvas::Locator.new(@dir)
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def locate(text, record = @record)
    @locator.locate(record, text)
  end

  def test_exact_text_in_body_not_front_matter
    result = locate("We are a small team that loves")
    assert_equal 1, result.length
    assert_equal "page.html", result[0][:file]
    assert_equal 5, result[0][:line]
    assert_equal "We are a small team that loves", result[0][:old_text]
  end

  def test_entities_match_their_characters
    result = locate("Jekyll & \"Ruby\" & more.")
    assert_equal 1, result.length
    assert_equal "Jekyll &amp; \"Ruby\" &#38; more.", result[0][:old_text]
    result = locate("Café è l'ora 'x' it's")
    assert_equal "Caf&eacute; &egrave; l&#39;ora &#x27;x&#x27; it's", result[0][:old_text]
  end

  def test_typographic_quotes_are_not_equivalent
    assert_empty locate("it’s")
    assert_empty locate("l’ora")
  end

  def test_whitespace_runs_match_any_whitespace
    result = locate("Two words across lines")
    assert_equal "Two   words\nacross lines", result[0][:old_text]
  end

  def test_liquid_spans_discarded
    assert_empty locate("page.title")
    assert_empty locate("page.title dynamic")
    assert_equal 1, locate("dynamic").length
  end

  def test_layouts_and_includes_and_liquid_overlap_in_layouts
    result = locate("Hardcoded footer")
    assert_equal ["_layouts/default.html"], result.map { |c| c[:file] }.uniq
    assert_equal 1, result.length # the copy inside {{ }} is discarded
    assert_equal "_includes/header.html", locate("Header words")[0][:file]
  end

  def test_word_boundaries
    assert_equal 1, locate("Home").length
    assert_equal 2, locate("Home", @record).length + 1
  end

  def test_markdown_pages_skip_own_file
    md = Record.new("page.html", "markdown", [], [])
    assert_empty locate("We are a small team that loves", md)
  end

  def test_unicode_offsets
    File.write(File.join(@dir, "u.html"), "<p>\u{1F600} caffè</p><p>target text</p>")
    record = Record.new("u.html", "html", [], [])
    c = locate("target text", record)[0]
    assert_equal "target text", File.read(File.join(@dir, "u.html"), encoding: "UTF-8")[c[:start]...c[:end]]
  end

  def test_not_found
    assert_empty locate("nothing like this here")
    assert_empty locate("   ")
  end
end
