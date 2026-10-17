# frozen_string_literal: true

require "liquid"
require_relative "errors"
require_relative "front_matter"
require_relative "markdown_blocks"
require_relative "paths"
require_relative "yaml_editor"

module JekyllCanvas
  # Applies one edit operation (spec-api.md, POST /edit): validate, write, rebuild.
  class Edits
    LIQUID_SPAN = /\{\{.*?\}\}|\{%.*?%\}/m

    def initialize(root:, builder:, watcher: nil)
      @root = root
      @builder = builder
      @watcher = watcher
    end

    def apply(op)
      @builder.synchronize do
        path, content = case op["op"]
                        when "yaml" then yaml(op)
                        when "literal" then literal(op)
                        when "md_block" then md_block(op)
                        when "body" then body(op)
                        when "front_matter_raw" then front_matter_raw(op)
                        when "file" then file(op)
                        else raise ApiError.new("invalid", "unknown op #{op['op'].inspect}")
                        end
        write(path, content)
        ok = @builder.build
        { ok: true, build_id: @builder.build_id, build_ms: @builder.last_build_ms, error: ok ? nil : @builder.error }
      end
    end

    # Used by other writers (media, discard, new document) to keep the watcher quiet.
    def write(abs, content)
      @watcher&.ignore(abs)
      File.binwrite(abs, content)
      @watcher&.acknowledge(abs)
    end

    private

    def resolve(file)
      Paths.resolve(@root, file, cache_dir: @builder.cache_dir)
    rescue Paths::Invalid => e
      raise ApiError.new("forbidden", e.message)
    end

    def read(abs)
      raise ApiError.new("not_found", "file not found") unless File.file?(abs)

      content = File.binread(abs).force_encoding("UTF-8")
      raise ApiError.new("invalid", "file is not valid UTF-8") unless content.valid_encoding?

      content
    end

    def require_fields(op, *names)
      names.each { |n| raise ApiError.new("invalid", "missing #{n}") unless op.key?(n) }
    end

    # --- yaml ---------------------------------------------------------------------------------

    def yaml(op)
      require_fields(op, "file", "keypath", "new")
      abs = resolve(op["file"])
      content = read(abs)
      keypath = op["keypath"]
      raise ApiError.new("invalid", "keypath must be a non-empty array") unless keypath.is_a?(Array) && !keypath.empty?

      old = op.key?("old") ? op["old"] : YamlEditor::UNSET
      if %w[.yml .yaml].include?(File.extname(abs).downcase)
        [abs, yaml_edit { YamlEditor.set(content, keypath, op["new"], old: old) }]
      else
        parts = FrontMatter.split(content)
        raise ApiError.new("invalid", "the file has no front matter") unless parts.front_matter?

        raw = yaml_edit { YamlEditor.set(parts.raw, keypath, op["new"], old: old) }
        [abs, content[0...parts.yaml_start] + raw + content[parts.yaml_end..]]
      end
    end

    def yaml_edit
      yield
    rescue YamlEditor::Conflict => e
      raise ApiError.new("conflict", e.message)
    rescue YamlEditor::NotFound => e
      raise ApiError.new("not_found", e.message)
    rescue YamlEditor::Error => e
      raise ApiError.new("invalid", e.message)
    end

    # --- literal ------------------------------------------------------------------------------

    def literal(op)
      require_fields(op, "file", "start", "end", "old_text", "new_text")
      abs = resolve(op["file"])
      content = read(abs)
      s = Integer(op["start"], exception: false)
      e = Integer(op["end"], exception: false)
      raise ApiError.new("invalid", "start/end must be integers") unless s && e && s >= 0 && s <= e

      raise ApiError.new("conflict", "the source text changed") unless content[s...e] == op["old_text"]

      content.scan(LIQUID_SPAN) do
        m = Regexp.last_match
        raise ApiError.new("invalid", "the text overlaps a Liquid tag") if s < m.end(0) && e > m.begin(0)
      end
      escaped = op["new_text"].to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
      [abs, content[0...s] + escaped + content[e..]]
    end

    # --- markdown block -----------------------------------------------------------------------

    def md_block(op)
      require_fields(op, "file", "start_line", "end_line", "old_markdown", "new_markdown")
      abs = resolve(op["file"])
      content = read(abs)
      first = Integer(op["start_line"], exception: false)
      last = Integer(op["end_line"], exception: false)
      lines = content.lines
      unless first && last && first >= 1 && last >= first && last <= lines.length
        raise ApiError.new("invalid", "line range out of bounds")
      end

      current = lines[(first - 1)...last].join.chomp.gsub("\r\n", "\n")
      raise ApiError.new("conflict", "the source lines changed") unless current == op["old_markdown"].to_s.gsub("\r\n", "\n")

      nl = content.include?("\r\n") ? "\r\n" : "\n"
      new_md = op["new_markdown"].to_s
      if new_md.empty?
        from = first - 1
        to = last
        if lines[to] && lines[to].strip.empty? then to += 1
        elsif from.positive? && lines[from - 1].strip.empty? then from -= 1
        end
        lines.slice!(from...to)
      else
        terminator = lines[last - 1][/(?:\r\n|\n|\r)\z/].to_s
        replacement = new_md.chomp.gsub("\r\n", "\n").gsub("\n", nl) + terminator
        lines[(first - 1)...last] = [replacement]
      end
      [abs, lines.join]
    end

    # --- whole body ---------------------------------------------------------------------------

    def body(op)
      require_fields(op, "file", "new_body")
      abs = resolve(op["file"])
      content = read(abs)
      parts = FrontMatter.split(content)
      if op.key?("old_body") && !op["old_body"].nil? && parts.body.gsub("\r\n", "\n") != op["old_body"].to_s.gsub("\r\n", "\n")
        raise ApiError.new("conflict", "the body changed")
      end

      new_body = op["new_body"].to_s.sub(/[\r\n]+\z/, "") + "\n"
      new_body = "\n#{new_body}" if parts.front_matter? && parts.body.start_with?("\n") && !new_body.start_with?("\n")
      [abs, content[0...parts.body_start] + new_body]
    end

    # --- whole front matter -------------------------------------------------------------------

    def front_matter_raw(op)
      require_fields(op, "file", "new_yaml")
      abs = resolve(op["file"])
      content = read(abs)
      yaml_text = op["new_yaml"].to_s
      yaml_text += "\n" unless yaml_text.empty? || yaml_text.end_with?("\n")
      unless FrontMatter.load_hash(yaml_text).is_a?(Hash)
        raise ApiError.new("invalid", "the front matter must be a YAML mapping")
      end

      parts = FrontMatter.split(content)
      new_content = if parts.front_matter?
                      content[0...parts.yaml_start] + yaml_text + content[parts.yaml_end..]
                    else
                      "---\n#{yaml_text}---\n#{content}"
                    end
      [abs, new_content]
    end

    # --- whole file (code editor) ---------------------------------------------------------------

    def file(op)
      require_fields(op, "file", "old_content", "new_content")
      abs = resolve(op["file"])
      raise ApiError.new("not_found", "file not found") unless File.file?(abs)
      raise ApiError.new("invalid", "binary files cannot be edited") if Paths.binary?(abs)

      content = read(abs)
      raise ApiError.new("conflict", "the file changed outside the editor") unless content == op["old_content"].to_s

      new_content = op["new_content"].to_s
      check_liquid(op["file"], new_content) unless op["force"] == true
      [abs, new_content]
    end

    # Liquid (strict) check for HTML/Markdown sources; front matter must be a YAML mapping.
    def check_liquid(file, content)
      return unless %w[liquid-html markdown].include?(Paths.language(file))

      parts = FrontMatter.split(content)
      if parts.front_matter? && FrontMatter.load_hash(parts.raw).nil?
        raise ApiError.new("invalid", "the front matter must be a YAML mapping")
      end

      offset = parts.body_start_line - 1
      begin
        Liquid::Template.parse(parts.body, error_mode: :strict, line_numbers: true)
      rescue Liquid::SyntaxError => e
        line = e.line_number&.+(offset)
        message = line ? e.message.sub(/\(line \d+\)/, "(line #{line})") : e.message
        raise ApiError.new("liquid_syntax", message, extra: { line: line })
      end
    end
  end
end
