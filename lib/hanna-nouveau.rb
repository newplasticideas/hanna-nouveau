# = A better RDoc HTML template
#
# Code rewritten by:
#   Erik Hollensbe <erik@hollensbe.org>
#
# RubyGems integration properly done by:
#   James Tucker (aka raggi)
#
# Original Authors:
#   Mislav Marohnic <mislav.marohnic@gmail.com>
#   Tony Strauss (http://github.com/DesigningPatterns)
#   Michael Granger <ged@FaerieMUD.org>, who had maintained the original RDoc template

require 'pathname'
require 'haml'
require 'sass'
require 'rdoc/rdoc'
require 'rdoc/generator'

class RDoc::Markup::ToHtml
  LIST_TYPE_TO_HTML[:LABEL] = ['<table class="rdoc-list label-list"><tbody>', '</tbody></table>']
  LIST_TYPE_TO_HTML[:NOTE]  = ['<table class="rdoc-list note-list"><tbody>',  '</tbody></table>']

  # CONTAINER_TAGS = {
  #     route:       "<route>",
  #     request:     "<request>",
  #     response:    "<response>",
  #     description: "<description>"
  # }.with_indifferent_access.freeze

  def list_item_start(list_item, list_type)
    case list_type
    when :BULLET, :LALPHA, :NUMBER, :UALPHA then
      '<li>'
    when :LABEL, :NOTE then
      "<tr><td class='label'>#{Array(list_item.label).map { |label| to_html(label) }.join('<br />')}</td><td>"
    else
      raise RDoc::Error, "Invalid list type: #{list_type.inspect}"
    end
  end

  def list_end_for(list_type)
    case list_type
    when :BULLET, :LALPHA, :NUMBER, :UALPHA then
      '</li>'
    when :LABEL, :NOTE then
      '</td></tr>'
    else
      raise RDoc::Error, "Invalid list type: #{list_type.inspect}"
    end
  end
end

class RDoc::Generator::Hanna
  STYLE            = 'styles.sass'.freeze
  LAYOUT           = 'layout.haml'.freeze

  INDEX_PAGE       = 'index.haml'.freeze
  CLASS_PAGE       = 'page.haml'.freeze
  METHOD_LIST_PAGE = 'method_list.haml'.freeze
  FILE_PAGE        = CLASS_PAGE
  SECTIONS_PAGE    = 'sections.haml'.freeze

  FILE_INDEX       = 'file_index.haml'.freeze
  CLASS_INDEX      = 'class_index.haml'.freeze
  METHOD_INDEX     = 'method_index.haml'.freeze
  CUSTOM_INDEX      = 'custom_index.haml'.freeze

  CLASS_DIR        = 'classes'.freeze
  FILE_DIR         = 'files'.freeze

  INDEX_OUT        = 'index.html'.freeze
  FILE_INDEX_OUT   = 'fr_file_index.html'.freeze
  CLASS_INDEX_OUT  = 'fr_class_index.html'.freeze
  METHOD_INDEX_OUT = 'fr_method_index.html'.freeze
  CUSTOM_INDEX_OUT  = 'fr_custom_index.html'.freeze
  STYLE_OUT        = File.join('css', 'style.css')

  DESCRIPTION = 'a HAML-based HTML generator that scales'.freeze

  # EPIC CUT AND PASTE TIEM NAO -- GG
  RDoc::RDoc.add_generator(self)

  def self.for(options)
    new(options)
  end

  def initialize(store, options)
    @options = options
    @store = store

    @templatedir = Pathname.new File.expand_path('hanna-nouveau/template_files', __dir__)

    @files      = nil
    @classes    = nil
    @methods    = nil
    @attributes = nil

    @basedir = Pathname.pwd.expand_path
  end

  def generate
    @outputdir = Pathname.new(@options.op_dir).expand_path(@basedir)

    @files      = @store.all_files.sort
    @classes    = @store.all_classes_and_modules.sort
    @methods    = @classes.map(&:method_list).flatten.sort
    @attributes = @classes.map(&:attributes).flatten.sort

    # Now actually write the output
    write_static_files
    generate_indexes
    generate_class_files
    generate_file_files
  rescue StandardError => err
    p [err.class.name, err.message, err.backtrace.join("\n  ")]
    raise
  end

  def write_static_files
    css_dir = outjoin('css')

    FileUtils.mkdir css_dir unless File.directory?(css_dir)

    File.open(File.join(css_dir, 'style.css'), 'w') { |f| f << Sass::Engine.new(File.read(templjoin(STYLE))).to_css }
  end

  # FIXME: refactor
  def generate_indexes
    @main_page_uri = begin
                       @files.find { |f| f.name == @options.main_page }.path
                     rescue StandardError
                       ''
                     end
    File.open(outjoin(INDEX_OUT), 'w') { |f| f << haml_file(templjoin(INDEX_PAGE)).to_html(binding) }

    generate_index(FILE_INDEX_OUT,   FILE_INDEX,   'File',     files: @files)
    generate_index(CLASS_INDEX_OUT,  CLASS_INDEX,  'Class',    classes: @classes)
    generate_index(METHOD_INDEX_OUT, METHOD_INDEX, 'Method',   methods: @methods, attributes: @attributes)
    generate_index(CUSTOM_INDEX_OUT,  CUSTOM_INDEX,  'Custom', classes: @classes, files: @files)
  end

  def generate_index(outfile, templfile, index_name, values)
    values[:stylesheet] = STYLE_OUT
    values[:list_title] = "#{index_name} Index"

    index = haml_file(templjoin(templfile))

    File.open(outjoin(outfile), 'w') do |f|
      f << with_layout(values) do
        index.to_html(binding, values)
      end
    end
  end

  def generate_file_files
    file_page = haml_file(templjoin(FILE_PAGE))
    method_list_page = haml_file(templjoin(METHOD_LIST_PAGE))

    # FIXME: non-Ruby files
    @files.each do |file|
      path = Pathname.new(file.path)
      stylesheet = Pathname.new(STYLE_OUT).relative_path_from(path.dirname)

      values = {
        file: file,
        entry: file,
        stylesheet: stylesheet,
        classmod: nil,
        title: file.base_name,
        list_title: nil,
        description: file.description
      }

      result = with_layout(values) do
        file_page.to_html(binding, values: values) do
          method_list_page.to_html(binding, values)
        end
      end

      # FIXME: XXX sanity check
      dir = path.dirname
      FileUtils.mkdir_p dir unless File.directory? dir

      File.open(outjoin(file.path), 'w') { |f| f << result }
    end
  end

  def generate_class_files
    class_page       = haml_file(templjoin(CLASS_PAGE))
    method_list_page = haml_file(templjoin(METHOD_LIST_PAGE))
    sections_page    = haml_file(templjoin(SECTIONS_PAGE))
    # FIXME: refactor

    @classes.each do |klass|
      outfile = classfile(klass)
      stylesheet = Pathname.new(STYLE_OUT).relative_path_from(outfile.dirname)
      sections = {}
      klass.each_section do |section, constants, attributes|
        method_types = []
        alias_types = []
        klass.methods_by_type(section).each do |type, visibilities|
          visibilities.each do |visibility, methods|
            aliases, methods = methods.partition(&:is_alias_for)
            method_types << ["#{visibility.to_s.capitalize} #{type.to_s.capitalize}", methods.sort] unless methods.empty?
            alias_types << ["#{visibility.to_s.capitalize} #{type.to_s.capitalize}", aliases.sort] unless aliases.empty?
          end
        end
        sections[section] = { constants: constants, attributes: attributes, method_types: method_types, alias_types: alias_types }
      end

      values = {
        file: klass.path,
        entry: klass,
        stylesheet: stylesheet,
        classmod: klass.type,
        title: klass.full_name,
        list_title: nil,
        description: klass.description,
        sections: sections
      }

      result = with_layout(values) do
        h = { values: values }
        class_page.to_html(binding, h) do
          method_list_page.to_html(binding, h) + sections_page.to_html(binding, h)
        end
      end

      # FIXME: XXX sanity check
      dir = outfile.dirname
      FileUtils.mkdir_p dir unless File.directory? dir

      File.open(outfile, 'w') { |f| f << result }
    end
  end

  def with_layout(values)
    layout = haml_file(templjoin(LAYOUT))
    layout.to_html(binding, values: values) { yield }
  end

  def sanitize_code_blocks(text)
    # text.gsub!(%r{\<p\>|\</p\>}, '') if text =~ %r{\<p\>|\</p\>}

    if text =~ /\<strong\>/
      text = text.split("\n")
      i = text.index { |e| e =~ /\<strong\>/ } + 1
      text = text[i..-1].join("\n")
    end

    text.gsub(%r{<pre>(.+?)</pre>}m) do
      code = Regexp.last_match(1).sub(/^\s*\n/, '')
      indent = code.gsub(/\n[ \t]*\n/, "\n").scan(/^ */).map(&:size).min
      code.gsub!(/^#{' ' * indent}/, '') if indent > 0
      code.to_s
    end
  end

  def humanize_file_name(file_name)
    if file_name =~ /^readme\.md$/i
      "Introduction"
    else
      file_name.gsub(".md", "").gsub(/^docs_/, "").humanize
    end
  end

  def generate_container_for(method, type, element, escaped: true)

    text = escaped ? parse_bespoke_tags_escaped(method, type) : parse_bespoke_tags(method, type)

    # bespoke_element_generator(method, text, type, element)
    "<#{element} class='#{type}-container'>#{text}</#{element}>"
  end

  def bespoke_element_generator(method, text, type, element)
    tag = case type
          when "description"
            "
              <div class='#{type}'>
                <#{element} class='#{type}-container'>
                  #{text}
                </#{element}>
              </div>
            "
          when "params"
            "
              <div class='params'>
                <h3 class='params-title'>
                  Attributes
                </h3>
                <#{element} class='#{type}-container'>
                  #{text}
                </#{element}>
              </div>
            "
          when "route"
            "
              <div class='#{type}'>
                <h3 class='params-title'
                  Route
                </h3>
                <pre id='#{method.aref}'>
                  <code class='http'>
                    <#{element} class='#{type}-container'>
                      #{text}
                    </#{element}>
                  </code>
                </pre>
              </div>
            "
          when "response"
            "
              <div class='response'>
                <h3 class='params-title'>
                  Example Response
                </h3>
                <pre id='#{method.aref}-source'>
                  <code class='json'>
                    <div class='response-container'
                      #{text}
                    </div>
                </pre>
              </div>
            "
          end
    tag


    # "<#{element} class='#{type}-container'>#{text}</#{element}>"
  end

  def is_documented?(method, type=nil)
    if type
      (method.text =~ %r{<#{type}>|</#{type}>}).nil? ? false : true
    else
      (method.text =~ regex_tag_scanner).nil? ? false : true
    end
  end

  def regex_tag_scanner
    %r{<description>.*</description\>|<heading>.*</heading\>|<params>.*</params\>|<route>.*</route\>|<response>.*</response\>|<request>.*</request\>}
  end

  def has_request_body?(method)
    (method.text =~ %r{<request>.*</request\>}).nil? ? false : true
  end

  def has_heading?(method)
    (method.text =~ %r{<heading>.*</heading\>}).nil? ? false : true
  end

  def has_response_body?
    (method.text =~ %r{<response>.*</response\>}).nil? ? false : true
  end

  def type_element_pairs
    [
      %w[description div],
      %w[params div],
      %w[route div],
      %w[request pre],
      %w[response div]
    ].freeze
  end

  def sanitize_title!
    return unless @selection =~ /\#/

    i = @selection.index { |e| e =~ /(\#)(?=\ \w)/ } + 1
    @selection = @selection[i..-1]
  end

  # probably should bring in nokogiri/libxml2 to do this right.. not sure if
  # it's worth it.
  def frame_link(content)
    content.gsub(%r{<a href="http://[^>]*>}).each do |tag|
      a_tag, rest = tag.split(' ', 2)
      rest.gsub!(/target="[^"]*"/, '')
      a_tag + ' target="_top" ' + rest
    end
  end

  def class_dir
    CLASS_DIR
  end

  def file_dir
    FILE_DIR
  end

  def h(html)
    CGI.escapeHTML(html)
  end

  # XXX may my sins be not visited upon my sons.
  def render_class_tree(entries, _parent = nil)
    namespaces = {}

    entries.sort.inject('') do |out, klass|
      unless namespaces[klass.full_name]
        text = if klass.name =~ /controller/i
                 klass.name.underscore.humanize.titleize[0..-12]
               else
                 klass.name.underscore.humanize.titleize
               end

        if klass.document_self
          out << '<li>'
          out << link_to(text, classfile(klass))
        end

        subentries = @classes.select { |x| x.full_name[/^#{klass.full_name}::/] }
        subentries.each { |x| namespaces[x.full_name] = true }
        out << "\n<ol>" + render_class_tree(subentries, klass) + "\n</ol>"

        out << '</li>' if klass.document_self
      end

      out
    end
  end

  def build_javascript_search_index(entries)
    result = "var search_index = [\n"
    entries.each do |entry|
      method_name = entry.name
      module_name = entry.parent_name
      # FIXME: link
      html = link_to_method(entry, [classfile(entry.parent), (begin
                                                                entry.aref
                                                              rescue StandardError
                                                                "method-#{entry.html_name}"
                                                              end)].join('#'))
      result << "  { method: '#{method_name.downcase}', " \
                "module: '#{module_name.downcase}', " \
                "html: '#{html}' },\n"
    end
    result << ']'
    result
  end

  def link_to(text, url = nil, classname = nil)
    class_attr = classname ? format(' class="%s"', classname) : ''

    if url
      %(<a href="#{url}"#{class_attr}>#{text}</a>)
    elsif classname
      %(<span#{class_attr}>#{text}</span>)
    else
      text
    end
  end

  # +method_text+ is in the form of "ago (ActiveSupport::TimeWithZone)".
  def link_to_method(entry, url = nil, classname = nil)
    method_name = begin
                    entry.pretty_name
                  rescue StandardError
                    entry.name
                  end
    module_name = begin
                    entry.parent_name
                  rescue StandardError
                    entry.name
                  end
    link_to %(<span class="method_name">#{h method_name}</span> <span class="module_name">(#{h module_name})</span>), url, classname
  end

  def classfile(klass)
    # FIXME: sloooooooow
    Pathname.new(File.join(CLASS_DIR, klass.full_name.split('::')) + '.html')
  end

  def outjoin(name)
    File.join(@outputdir, name)
  end

  def templjoin(name)
    File.join(@templatedir, name)
  end

  def haml_file(file)
    Haml::Engine.new(File.read(file), format: :html4)
  end

  private

    def parse_bespoke_tags_escaped(text, type)
      text = text.scan(%r{&lt;#{type}&gt;.*&lt;\/#{type}\&gt;}m)
      text = text.is_a?(Array) ? text[0] : text

      if text
        text.gsub!(%r{&lt;#{type}&gt;|&lt;\/#{type}\&gt;}, '')
      else
        text = ""
      end

      text
    end

    def parse_bespoke_tags(text, type)
      text = text.gsub("\n", '{{{{{this_is_a_new_line}}}}}')
      text = text.scan(%r{<#{type}>.*<\/#{type}\>})
      text = text.is_a?(Array) ? text[0] : text

      if text
        text.gsub!(%r{<#{type}>|<\/#{type}\>}, '')
        text.delete!('#')
        text.gsub!('{{{{{this_is_a_new_line}}}}}', "\n")
        text.gsub!(/\n\ *\n\ */, "\n\n")
        text.gsub!(/\ {6}/, '')
      else
        text = ""
      end

      text
    end
end
