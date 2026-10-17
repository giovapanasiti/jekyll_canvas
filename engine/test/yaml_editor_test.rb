# frozen_string_literal: true

require "test_helper"
require "jekyll_canvas/yaml_editor"

class YamlEditorTest < Minitest::Test
  Y = JekyllCanvas::YamlEditor

  # Returns [new_source, original line indexes that were replaced]: everything between the
  # common prefix and the common suffix of the two line lists.
  def edit(src, path, value, **opts)
    out = Y.set(src, path, value, **opts)
    a = src.split(/(?<=\n)/)
    b = out.split(/(?<=\n)/)
    prefix = 0
    prefix += 1 while prefix < a.length && prefix < b.length && a[prefix] == b[prefix]
    suffix = 0
    suffix += 1 while suffix < a.length - prefix && suffix < b.length - prefix && a[-1 - suffix] == b[-1 - suffix]
    [out, (prefix...(a.length - suffix)).to_a]
  end

  def assert_value(out, path, expected)
    assert_equal expected, Y.get(out, path)
  end

  def test_plain_scalar
    src = "# top comment\ntitle: Hello\nother: keep # note\n\nlast: 1\n"
    out, changed = edit(src, %w[title], "Ciao")
    assert_equal "# top comment\ntitle: Ciao\nother: keep # note\n\nlast: 1\n", out
    assert_equal [1], changed
  end

  def test_old_value_conflict
    assert_raises(Y::Conflict) { Y.set("a: x\n", %w[a], "y", old: "z") }
    assert_equal "a: y\n", Y.set("a: x\n", %w[a], "y", old: "x")
  end

  def test_comment_on_same_line_kept
    out, changed = edit("title: Foo # note\nb: 2\n", %w[title], "Bar")
    assert_equal "title: Bar # note\nb: 2\n", out
    assert_equal [0], changed
  end

  def test_single_quoted_kept
    out, = edit("a: 'it''s'\n", %w[a], "l'albero")
    assert_equal "a: 'l''albero'\n", out
  end

  def test_double_quoted_kept_and_escaped
    out, = edit(%(a: "x"\nb: 1\n), %w[a], %(say "hi"\\now))
    assert_equal %(a: "say \\"hi\\"\\\\now"\nb: 1\n), out
    assert_value out, %w[a], %(say "hi"\\now)
  end

  def test_plain_becomes_quoted_when_needed
    {
      "a: b" => %("a: b"), "x #y" => %("x #y"), "ends:" => %("ends:"), "*star" => %("*star"),
      "&amp" => %("&amp"), "- dash" => %("- dash"), "yes" => %("yes"), "null" => %("null"),
      "2026" => %("2026"), "1.0" => %("1.0"), "2026-10-17" => %("2026-10-17"), "~" => %("~"),
      "#hash" => %("#hash"), "@at" => %("@at"), "%pct" => %("%pct"), "[x]" => %("[x]"),
      " lead" => %(" lead"), "" => %("")
    }.each do |value, rendered|
      out, changed = edit("a: old\nb: 2\n", %w[a], value)
      assert_equal "a: #{rendered}\nb: 2\n", out, "value #{value.inspect}"
      assert_equal [0], changed
      assert_value out, %w[a], value
    end
  end

  def test_plain_stays_plain
    ["He said: it's \"fine\"".sub(": ", " - "), "Co-founder, CTO", "50% off", "a#b", "x:y"].each do |v|
      out, = edit("a: old\n", %w[a], v)
      assert_equal "a: #{v}\n", out
    end
  end

  def test_unicode
    out, changed = edit("t: Ciao\nu: x\n", %w[t], "Perché è così? \u{1F600} caffè")
    assert_equal "t: Perché è così? \u{1F600} caffè\nu: x\n", out
    assert_equal [0], changed
    out, = edit("t: \"Ciao à\"\n", %w[t], "Ora è là \u{1F680}")
    assert_equal "t: \"Ora è là \u{1F680}\"\n", out
    # offsets must be right after multibyte content on the same line
    out, = edit("t: \u{1F600} é\nnext: old\n", %w[next], "new")
    assert_equal "t: \u{1F600} é\nnext: new\n", out
  end

  def test_multiline_replacement_is_double_quoted
    out, changed = edit("a: one\nb: 2\n", %w[a], "line1\nline2")
    assert_equal %(a: "line1\\nline2"\nb: 2\n), out
    assert_equal [0], changed
    assert_value out, %w[a], "line1\nline2"
  end

  def test_multiline_original_scalar_collapsed
    src = "a: 'x\n  y'\nb: plain\n  continued\nc: 3\n"
    out, = edit(src, %w[b], "short")
    assert_equal "a: 'x\n  y'\nb: short\nc: 3\n", out
    out, = edit(src, %w[a], "z")
    assert_equal "a: 'z'\nb: plain\n  continued\nc: 3\n", out
  end

  def test_non_string_values
    out, = edit("n: 1\ns: x\n", %w[n], 42)
    assert_equal "n: 42\ns: x\n", out
    out, = edit("n: 1\ns: x\n", %w[s], true)
    assert_equal "n: 1\ns: true\n", out
    out, = edit("n: 1\ns: x\n", %w[s], nil)
    assert_equal "n: 1\ns: null\n", out
    out, = edit("n: 1\ns: x\n", %w[n], 2.5)
    assert_equal "n: 2.5\ns: x\n", out
    out, = edit("n: \"2026\"\n", %w[n], 2027)
    assert_equal "n: 2027\n", out
  end

  def test_empty_value_gets_filled
    out, changed = edit("a:\nb: 1\n", %w[a], "hello")
    assert_equal "a: hello\nb: 1\n", out
    assert_equal [0], changed
    out, = edit("a: # why\nb: 1\n", %w[a], "hello")
    assert_equal "a: hello # why\nb: 1\n", out
  end

  def test_literal_block_scalar
    src = "k:\n  desc: |\n    first\n    second\n\n  next: 1\n"
    out, changed = edit(src, %w[k desc], "uno\ndue\ntre\n")
    assert_equal "k:\n  desc: |\n    uno\n    due\n    tre\n\n  next: 1\n", out
    assert_equal [2, 3], changed
    assert_value out, %w[k desc], "uno\ndue\ntre\n"
  end

  def test_literal_block_chomp_variants
    src = "a: |\n  x\nb: 1\n"
    out, = edit(src, %w[a], "no newline")
    assert_equal "a: |-\n  no newline\nb: 1\n", out
    out, = edit(src, %w[a], "keep\n\n\n")
    assert_equal "a: |+\n  keep\n\n\nb: 1\n", out
    assert_value out, %w[a], "keep\n\n\n"
    out, = edit(src, %w[a], "")
    assert_value out, %w[a], ""
  end

  def test_literal_block_with_comment_and_deeper_indent
    src = "root:\n  - text: |-  # note\n        deep\n        indent\n    other: 1\n"
    out, = edit(src, %w[root 0 text], "changed\nlines")
    assert_equal "root:\n  - text: |-  # note\n        changed\n        lines\n    other: 1\n", out
  end

  def test_literal_block_last_in_file_without_newline
    out, = edit("a: |-\n  x\n  y", %w[a], "z")
    assert_equal "a: |-\n  z", out
  end

  def test_literal_block_leading_spaces_uses_indent_indicator
    out, = edit("a: |\n  x\nb: 1\n", %w[a], "  indented\nplain\n")
    assert_value out, %w[a], "  indented\nplain\n"
  end

  def test_folded_block_scalar
    src = "a: >\n  one two\n  three\nb: 1\n"
    out, = edit(src, %w[a], "alpha\nbeta\n")
    assert_equal "a: >\n  alpha\n\n  beta\nb: 1\n", out
    assert_value out, %w[a], "alpha\nbeta\n"
    out, = edit(src, %w[a], "alpha\n\nbeta")
    assert_value out, %w[a], "alpha\n\nbeta"
  end

  def test_block_scalar_to_number_and_empty
    out, = edit("a: |\n  x\nb: 1\n", %w[a], 5)
    assert_equal "a: 5\nb: 1\n", out
  end

  def test_nested_sequence_of_mappings
    src = "items:\n  - title: A\n    n: 1\n  - title: B\n    n: 2\n  - title: C # third\n    n: 3\n"
    out, changed = edit(src, %w[items 2 title], "Gamma")
    assert_equal src.sub("title: C # third", "title: Gamma # third"), out
    assert_equal [5], changed
    assert_value out, ["items", 2, "title"], "Gamma"
    assert_equal "B", Y.get(out, ["items", "1", "title"])
  end

  def test_nav_style_language_leaves
    src = "- label:\n    en: Home\n    it: Casa\n  url: /\n- label:\n    en: About\n    it: Chi siamo\n  url: /about/\n"
    out, changed = edit(src, [1, "label", "it"], "Chi siamo noi")
    assert_equal [6], changed
    assert_value out, [1, "label", "it"], "Chi siamo noi"
  end

  def test_flow_sequence_replace
    src = "stack: [Ruby, Rails]\nx: 1\n"
    out, changed = edit(src, %w[stack], ["Ruby", "Rails", "Hotwire", "c, d", 3])
    assert_equal "stack: [Ruby, Rails, Hotwire, \"c, d\", 3]\nx: 1\n", out
    assert_equal [0], changed
    out, = edit(src, %w[stack], [])
    assert_equal "stack: []\nx: 1\n", out
  end

  def test_block_sequence_replace
    src = "tags:\n  - one\n  - two # c\n  - three\nnext: 1\n"
    out, changed = edit(src, %w[tags], %w[uno due])
    assert_equal "tags:\n  - uno\n  - due\nnext: 1\n", out
    assert_equal [1, 2, 3], changed
    out, = edit(src, %w[tags], [])
    assert_equal "tags: []\nnext: 1\n", out
    out, = edit("tags:\n- a\n- b\nz: 1\n", %w[tags], %w[x y z])
    assert_equal "tags:\n- x\n- y\n- z\nz: 1\n", out
  end

  def test_single_item_in_sequence_of_scalars
    out, = edit("tags:\n  - one\n  - two\n", ["tags", 1], "dos")
    assert_equal "tags:\n  - one\n  - dos\n", out
    out, = edit("tags: [one, two]\n", ["tags", 0], "uno")
    assert_equal "tags: [uno, two]\n", out
    out, = edit("tags: [one, two]\n", ["tags", 0], "a, b")
    assert_equal "tags: [\"a, b\", two]\n", out
  end

  def test_flow_mapping_value
    out, = edit("a: {x: 1, y: hello}\nb: 2\n", %w[a y], "ciao")
    assert_equal "a: {x: 1, y: ciao}\nb: 2\n", out
    out, = edit("a: {x: 1, y: hello}\nb: 2\n", %w[a y], "ci,ao")
    assert_equal "a: {x: 1, y: \"ci,ao\"}\nb: 2\n", out
  end

  def test_crlf_files
    src = "title: Old\r\ndesc: |\r\n  a\r\n  b\r\nz: 1\r\n"
    out, = edit(src, %w[title], "New")
    assert_equal "title: New\r\ndesc: |\r\n  a\r\n  b\r\nz: 1\r\n", out
    out, = edit(src, %w[desc], "x\ny\n")
    assert_equal "title: Old\r\ndesc: |\r\n  x\r\n  y\r\nz: 1\r\n", out
    out = Y.set(src, %w[added], "v")
    assert_equal "title: Old\r\ndesc: |\r\n  a\r\n  b\r\nz: 1\r\nadded: v\r\n", out
  end

  def test_add_key
    out = Y.set("a: 1\nb: 2\n", %w[c], "three")
    assert_equal "a: 1\nb: 2\nc: three\n", out
    out = Y.set("a: 1\nb: 2", %w[c], "three")
    assert_equal "a: 1\nb: 2\nc: three", out
    out = Y.set("# only comment\n", %w[c], "x")
    assert_equal "# only comment\nc: x\n", out
    out = Y.set("", %w[c], ["x", "y"])
    assert_equal "c: [x, y]\n", out
  end

  def test_add_key_nested_and_after_block_scalar_and_comment
    src = "top:\n  a: 1\n  b: |\n    text  \n    more\n\n# trailing\nother: 2\n"
    out = Y.set(src, %w[top c], "new")
    assert_equal "top:\n  a: 1\n  b: |\n    text  \n    more\n  c: new\n\n# trailing\nother: 2\n", out
    out = Y.set("a: 1 # c1\n# c2\n", %w[b], "x")
    assert_equal "a: 1 # c1\nb: x\n# c2\n", out
    out = Y.set("- a: 1\n  b: 2\n", [0, "c"], "x")
    assert_equal "- a: 1\n  b: 2\n  c: x\n", out
  end

  def test_add_key_with_conflicting_old
    assert_raises(Y::Conflict) { Y.set("a: 1\n", %w[b], "x", old: "y") }
  end

  def test_add_key_needing_quotes
    out = Y.set("a: 1\n", %w[b], "x: y")
    assert_equal "a: 1\nb: \"x: y\"\n", out
  end

  def test_front_matter_like_region
    src = "layout: default\ntitle: \"Servizi\"\nlang: it\n"
    out, changed = edit(src, %w[title], "Servizi AI")
    assert_equal "layout: default\ntitle: \"Servizi AI\"\nlang: it\n", out
    assert_equal [1], changed
  end

  def test_unsupported_cases
    assert_raises(Y::Unsupported) { Y.set("a: &x one\nb: *x\n", %w[a], "two") }
    assert_raises(Y::Unsupported) { Y.set("a: &x one\nb: *x\n", %w[b], "two") }
    assert_raises(Y::Unsupported) { Y.set("base: &b\n  x: 1\nd:\n  <<: *b\n", %w[d x], 2) }
    assert_raises(Y::Unsupported) { Y.set("a: {}\n", %w[a k], "v") }
    assert_raises(Y::Unsupported) { Y.set("a: !!str 5\n", %w[a], "6") }
  end

  def test_invalid_and_missing
    assert_raises(Y::Invalid) { Y.set("a: [unclosed\n", %w[a], "x") }
    assert_raises(Y::NotFound) { Y.get("a: 1\n", %w[zzz]) }
    assert_raises(Y::NotFound) { Y.set("a: 1\n", %w[x y z], "v") }
  end

  def test_no_op_returns_same_source
    src = "a:   1   # c\n"
    assert_equal src, Y.set(src, %w[a], 1)
  end

  def test_value_with_tab_and_control_chars
    out, = edit("a: x\n", %w[a], "tab\there")
    assert_equal %(a: "tab\\there"\n), out
    assert_value out, %w[a], "tab\there"
  end

  def test_keys_with_numbers_and_quotes
    src = "2024: old\n\"quoted key\": v\n"
    out, = edit(src, %w[2024], "new")
    assert_equal "2024: new\n\"quoted key\": v\n", out
    out, = edit(src, ["quoted key"], "w")
    assert_equal "2024: old\n\"quoted key\": w\n", out
  end

  def test_real_world_i18n_shape
    src = <<~YAML
      # English strings
      home:
        hero:
          title: We build AI products
          subtitle: "Small team, big results"
          cta: 'Talk to us'
        items:
          - name: One
            body: >-
              Folded text
              goes here
          - name: Two
            body: |
              Literal
      footer:
        copy: © 2026 Monte del Gallo # keep
    YAML
    out, changed = edit(src, %w[home hero subtitle], "Piccolo team, grandi risultati")
    assert_equal [4], changed
    out, changed = edit(out, %w[footer copy], "© 2027 Monte del Gallo")
    assert_equal [15], changed
    assert_includes out, "© 2027 Monte del Gallo # keep"
    out, = edit(out, ["home", "items", 0, "body"], "Nuovo testo lungo")
    assert_equal "Nuovo testo lungo\n".sub("\n", ""), Y.get(out, ["home", "items", 0, "body"])
  end

  FUZZ_ALPHABET = ["a", "Z", " ", " ", ":", "#", "'", "\"", "\\", "-", "*", "&", "!", "|", ">", "%", "@", "`",
                   "[", "]", "{", "}", ",", "?", "\n", "\n", "\t", "\r", "0", "1", ".", "\u00E8", "\u{1F600}",
                   "yes", "null", "~", "=", "<<"].freeze

  def test_fuzz_round_trip_every_style
    rng = Random.new(42)
    sources = {
      plain: "pre: 1\nk: old\npost: 2\n",
      single: "pre: 1\nk: 'old'\npost: 2\n",
      double: "pre: 1\nk: \"old\"\npost: 2\n",
      literal: "pre: 1\nk: |\n  old\n  text\npost: 2\n",
      folded: "pre: 1\nk: >\n  old\n  text\npost: 2\n",
      nested_literal: "a:\n  - pre: 1\n    k: |-\n      old\n  - post: 2\n",
      flow: "pre: 1\nk: [old, 1]\npost: 2\n"
    }
    paths = Hash.new(%w[k]).merge(nested_literal: ["a", 0, "k"])
    500.times do
      value = Array.new(rng.rand(0..8)) { FUZZ_ALPHABET[rng.rand(FUZZ_ALPHABET.length)] }.join
      sources.each do |style, src|
        next if style == :flow
        out = Y.set(src, paths[style], value)
        assert_equal value, Y.get(out, paths[style]), "#{style} #{value.inspect}"
        assert_equal 1, Y.get(out, ["pre"]) if paths[style] == %w[k]
        assert_equal 2, Y.get(out, ["post"]) if paths[style] == %w[k]
        assert out.start_with?("pre: 1\n") || style == :nested_literal
      end
      list = [value, "x", 3]
      out = Y.set(sources[:flow], %w[k], list)
      assert_equal list, Y.get(out, %w[k])
    end
  end
end
