# frozen_string_literal: true

require "test_helper"
require "jekyll_canvas/markdown_blocks"
require "kramdown-parser-gfm"

class MarkdownBlocksTest < Minitest::Test
  MB = JekyllCanvas::MarkdownBlocks

  BODY = <<~MD

    # Title

    Para one
    continues

    - a
    - b

    <figure>
      <img src="x">
    </figure>

    ```ruby
    puts 1

    puts 2
    ```

    Setext
    ======

    | a | b |
    |---|---|
    | 1 | 2 |

    > quote

    ---

    {: .lead}
    Text with IAL
    {: .cls}

    1. one
    2. two
  MD

  def summary
    MB.blocks(BODY).map { |b| [b.start_line, b.end_line, b.type, b.header_level] }
  end

  def test_block_ranges_and_types
    assert_equal [
      [2, 2, :header, 1], [4, 5, :p, nil], [7, 8, :ul, nil], [10, 12, :html_element, nil],
      [14, 18, :codeblock, nil], [20, 21, :header, 1], [23, 25, :table, nil], [27, 27, :blockquote, nil],
      [29, 29, :hr, nil], [32, 33, :p, nil], [35, 36, :ol, nil]
    ], summary
  end

  def test_block_at
    assert_equal 4, MB.block_at(BODY, 5).start_line
    assert_equal :codeblock, MB.block_at(BODY, 16).type
    assert_nil MB.block_at(BODY, 3)
    assert_nil MB.block_at(BODY, 99)
  end

  def test_empty_body
    assert_empty MB.blocks("")
    assert_empty MB.blocks("\n\n")
  end
end
