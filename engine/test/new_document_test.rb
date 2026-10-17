# frozen_string_literal: true

require "test_helper"
require "date"
require "jekyll_canvas/errors"
require "jekyll_canvas/new_document"
require "jekyll_canvas/records"

class NewDocumentTest < Minitest::Test
  ND = JekyllCanvas::NewDocument

  def test_slugify
    assert_equal "il-mio-post-e-gia-cosi", ND.slugify("Il mio Post è già così!")
    assert_equal "hello-world-2026", ND.slugify("  Hello,   World -- 2026 ")
    assert_equal "uber-cafe", ND.slugify("Über Café")
    assert_equal "", ND.slugify("???")
    assert_equal "a-b", ND.slugify("a/b")
  end

  def setup
    @dir = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(@dir, "_services/it"))
    File.write(File.join(@dir, "_services/it/old-it.md"), <<~MD)
      ---
      title: Vecchio servizio
      lang: it
      page_id: old
      layout: service
      order: 3
      permalink: /servizi/vecchio/
      featured: true
      tags: [a, b]
      cta:
        label: Scopri
        url: /contatti/
        deep:
          x: 1
      image: /a.webp
      ---

      Corpo.
    MD
    File.write(File.join(@dir, "_services/en-one.md"), "---\ntitle: One\nlang: en\n---\n\nBody\n")
    @records = JekyllCanvas::Records.new
    add("/it/servizi/vecchio/", "_services/it/old-it.md", "it")
    add("/services/one/", "_services/en-one.md", "en")
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def add(url, file, lang)
    r = JekyllCanvas::Record.new
    r.url = url
    r.file = file
    r.lang = lang
    r.doc_lang = lang
    r.collection = "services"
    r.kind = "document"
    r.format = "markdown"
    r.html = true
    @records.add(r)
  end

  def creator(languages = %w[en it])
    ND.new(root: @dir, records: @records, info: { languages: languages, collections_dir: "" })
  end

  def test_template_is_newest_sibling_in_same_language
    file = creator.create(collection: "services", lang: "it", title: "Nuovo Servizio", date: "2026-10-17")
    assert_equal "_services/it/nuovo-servizio.md", file
    assert_equal <<~MD, File.read(File.join(@dir, file), encoding: "UTF-8")
      ---
      title: Nuovo Servizio
      lang: it
      page_id: nuovo-servizio
      layout: service
      order:
      permalink: /servizi/nuovo-servizio/
      featured: false
      tags: []
      cta:
        label: ""
        url: ""
        deep: {}
      image: ""
      ---

      Scrivi qui il testo.
    MD
  end

  def test_falls_back_to_other_language_template_dir
    future = Time.now + 60
    File.utime(future, future, File.join(@dir, "_services/it/old-it.md"))
    file = creator.create(collection: "services", lang: "de", title: "Dienst", slug: "dienst")
    assert_equal "_services/it/dienst.md", file # newest of any language; same directory as the template
  end

  def test_no_template_defaults
    file = creator.create(collection: "notes", lang: "en", title: "A note")
    assert_equal "_notes/a-note.md", file
    assert_equal "---\ntitle: A note\nlang: en\n---\n\nScrivi qui il testo.\n", File.read(File.join(@dir, file))
    file = creator(%w[en]).create(collection: "posts", lang: "en", title: "First", date: "2026-01-02")
    assert_equal "_posts/2026-01-02-first.md", file
    assert_equal "---\ntitle: First\ndate: 2026-01-02\n---\n\nScrivi qui il testo.\n", File.read(File.join(@dir, file))
  end

  def test_refuses_existing_file_and_bad_input
    creator.create(collection: "services", lang: "it", title: "Dup")
    err = assert_raises(JekyllCanvas::ApiError) { creator.create(collection: "services", lang: "it", title: "Dup") }
    assert_equal "conflict", err.code
    assert_equal "invalid", assert_raises(JekyllCanvas::ApiError) { creator.create(collection: "services", lang: "it", title: "???") }.code
  end

  def test_quoting_of_special_titles
    file = creator.create(collection: "services", lang: "it", title: "Che cos'è: AI? # sì", slug: "ai")
    assert_includes File.read(File.join(@dir, file), encoding: "UTF-8"), %(title: "Che cos'è: AI? # sì"\n)
  end
end
