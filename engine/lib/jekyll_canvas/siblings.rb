# frozen_string_literal: true

require_relative "front_matter"
require_relative "yaml_editor"

module JekyllCanvas
  # Other-language versions of a traced string (spec-api.md, "siblings").
  class Siblings
    def initialize(root:, languages:, records:)
      @root = root
      @languages = languages
      @records = records
    end

    # entry: {file:, keypath:, source:} -> [{lang:, file:, keypath:, value:}]
    def for(entry)
      found = []
      found.concat(by_file_segment(entry))
      found.concat(by_keypath_segment(entry))
      found.concat(by_page_id(entry)) if entry[:source] == "front_matter"
      found.uniq { |s| [s[:lang], s[:file], s[:keypath]] }
           .sort_by { |s| @languages.index(s[:lang]) || @languages.length }
    end

    private

    # _data/i18n/en.yml, _data/en/strings.yml
    def by_file_segment(entry)
      return [] unless entry[:source] == "data"

      segments = entry[:file].split("/")
      idx = segments.each_with_index.find { |seg, i| @languages.include?(i == segments.length - 1 ? File.basename(seg, ".*") : seg) }&.last
      return [] unless idx

      own = segments[idx]
      ext = idx == segments.length - 1 ? File.extname(own) : ""
      own_lang = File.basename(own, ext)
      (@languages - [own_lang]).filter_map do |lang|
        swapped = segments.dup
        swapped[idx] = "#{lang}#{ext}"
        value_at(swapped.join("/"), entry[:keypath], entry[:source]) { |v| { lang: lang, file: swapped.join("/"), keypath: entry[:keypath], value: v } }
      end
    end

    # nav.yml: [3, "en"]
    def by_keypath_segment(entry)
      idx = entry[:keypath].each_index.find { |i| entry[:keypath][i].is_a?(String) && @languages.include?(entry[:keypath][i]) }
      return [] unless idx

      own = entry[:keypath][idx]
      (@languages - [own]).filter_map do |lang|
        path = entry[:keypath].dup
        path[idx] = lang
        value_at(entry[:file], path, entry[:source]) { |v| { lang: lang, file: entry[:file], keypath: path, value: v } }
      end
    end

    # Front matter of paired documents (same page_id, other language).
    def by_page_id(entry)
      own = @records.find { |r| r.file == entry[:file] }
      return [] unless own && !own.page_id.to_s.empty?

      own_lang = own.doc_lang || own.lang
      @records.select { |r| r.page_id == own.page_id && r.collection == own.collection && r.file != own.file }
              .group_by { |r| r.doc_lang || r.lang }
              .reject { |lang, _| lang == own_lang }
              .filter_map do |lang, recs|
        file = recs.first.file
        value_at(file, entry[:keypath], "front_matter") { |v| { lang: lang, file: file, keypath: entry[:keypath], value: v } }
      end
    end

    def value_at(file, keypath, source)
      path = File.join(@root, file)
      return nil unless File.file?(path)

      content = File.binread(path).force_encoding("UTF-8")
      text = if source == "front_matter" || !%w[.yml .yaml].include?(File.extname(path).downcase)
               FrontMatter.split(content).raw
             else
               content
             end
      return nil if text.nil?

      value = YamlEditor.get(text, keypath)
      value.is_a?(String) ? yield(value) : nil
    rescue YamlEditor::Error
      nil
    end
  end
end
