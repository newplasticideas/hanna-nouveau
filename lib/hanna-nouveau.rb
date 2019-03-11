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
      "<tr><td class='label'>#{Array(list_item.label).map{|label| to_html(label)}.join("<br />")}</td><td>"
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
  STYLE            = 'styles.sass'
  LAYOUT           = 'layout.haml'

  INDEX_PAGE       = 'index.haml'
  CLASS_PAGE       = 'page.haml'
  METHOD_LIST_PAGE = 'method_list.haml'
  FILE_PAGE        = CLASS_PAGE
  SECTIONS_PAGE    = 'sections.haml'

  FILE_INDEX       = 'file_index.haml'
  CLASS_INDEX      = 'class_index.haml'
  METHOD_INDEX     = 'method_index.haml'

  CLASS_DIR        = 'classes'
  FILE_DIR         = 'files'

  INDEX_OUT        = 'index.html'
  FILE_INDEX_OUT   = 'fr_file_index.html'
  CLASS_INDEX_OUT  = 'fr_class_index.html'
  METHOD_INDEX_OUT = 'fr_method_index.html'
  STYLE_OUT        = File.join('css', 'style.css')

  DESCRIPTION = 'a HAML-based HTML generator that scales'

  # EPIC CUT AND PASTE TIEM NAO -- GG
  RDoc::RDoc.add_generator( self )

  def self::for( options )
    new( options )
  end

  def initialize( store, options )
    @options = options
    @store = store

    @templatedir = Pathname.new File.expand_path('../hanna-nouveau/template_files', __FILE__)

    @files      = nil
    @classes    = nil
    @methods    = nil
    @attributes = nil

    @basedir = Pathname.pwd.expand_path
  end

  def generate
    @outputdir = Pathname.new( @options.op_dir ).expand_path( @basedir )

    @files      = @store.all_files.sort
    @classes    = @store.all_classes_and_modules.sort
    @methods    = @classes.map {|m| m.method_list }.flatten.sort
    @attributes = @classes.map(&:attributes).flatten.sort

    # Now actually write the output
    write_static_files
    generate_indexes
    generate_class_files
    generate_file_files

  rescue StandardError => err
    p [ err.class.name, err.message, err.backtrace.join("\n  ") ]
    raise
  end

  def write_static_files
    css_dir = outjoin('css')

    unless File.directory?(css_dir)
      FileUtils.mkdir css_dir
    end

    File.open(File.join(css_dir, 'style.css'), 'w') { |f| f << Sass::Engine.new(File.read(templjoin(STYLE))).to_css }
  end

  # FIXME refactor
  def generate_indexes
    @main_page_uri = @files.find { |f| f.name == @options.main_page }.path rescue ''
    File.open(outjoin(INDEX_OUT), 'w') { |f| f << haml_file(templjoin(INDEX_PAGE)).to_html(binding) }

    generate_index(FILE_INDEX_OUT,   FILE_INDEX,   'File',   { :files => @files})
    generate_index(CLASS_INDEX_OUT,  CLASS_INDEX,  'Class',  { :classes => @classes })
    generate_index(METHOD_INDEX_OUT, METHOD_INDEX, 'Method', { :methods => @methods, :attributes => @attributes })
  end

  def generate_index(outfile, templfile, index_name, values)
    values.merge!({
      :stylesheet => STYLE_OUT,
      :list_title => "#{index_name} Index"
    })

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

    # FIXME non-Ruby files
    @files.each do |file|
      path = Pathname.new(file.path)
      stylesheet = Pathname.new(STYLE_OUT).relative_path_from(path.dirname)
      
      values = { 
        :file => file, 
        :entry => file,
        :stylesheet => stylesheet,
        :classmod => nil, 
        :title => file.base_name, 
        :list_title => nil,
        :description => file.description
      } 

      result = with_layout(values) do 
        file_page.to_html(binding, :values => values) do 
          method_list_page.to_html(binding, values) 
        end
      end

      # FIXME XXX sanity check
      dir = path.dirname
      unless File.directory? dir
        FileUtils.mkdir_p dir
      end

      File.open(outjoin(file.path), 'w') { |f| f << result }
    end
  end

  def generate_class_files
    class_page       = haml_file(templjoin(CLASS_PAGE))
    method_list_page = haml_file(templjoin(METHOD_LIST_PAGE))
    sections_page    = haml_file(templjoin(SECTIONS_PAGE))
    # FIXME refactor

    @classes.each do |klass|
      outfile = classfile(klass)
      stylesheet = Pathname.new(STYLE_OUT).relative_path_from(outfile.dirname)
      sections = {}
      klass.each_section do |section, constants, attributes|
        method_types = []
        alias_types = []
        klass.methods_by_type(section).each do |type, visibilities|
          visibilities.each do |visibility, methods|
            aliases, methods = methods.partition{|x| x.is_alias_for}
            method_types << ["#{visibility.to_s.capitalize} #{type.to_s.capitalize}", methods.sort] unless methods.empty?
            alias_types << ["#{visibility.to_s.capitalize} #{type.to_s.capitalize}", aliases.sort] unless aliases.empty?
          end
        end
        sections[section] = {:constants=>constants, :attributes=>attributes, :method_types=>method_types, :alias_types=>alias_types}
      end

      values = { 
        :file => klass.path, 
        :entry => klass,
        :stylesheet => stylesheet,
        :classmod => klass.type,
        :title => klass.full_name,
        :list_title => nil,
        :description => klass.description,
        :sections => sections
      } 

      result = with_layout(values) do 
        h = {:values => values}
        class_page.to_html(binding, h) do 
          method_list_page.to_html(binding, h) + sections_page.to_html(binding, h)
        end
      end

      # FIXME XXX sanity check
      dir = outfile.dirname
      unless File.directory? dir
        FileUtils.mkdir_p dir
      end

      File.open(outfile, 'w') { |f| f << result }
    end
  end

  def with_layout(values)
    layout = haml_file(templjoin(LAYOUT))
    layout.to_html(binding, :values => values) { yield }
  end

  def sanitize_code_blocks(text)

    if text =~ /\<p\>|\<\/p\>/
      text.gsub!(/\<p\>|\<\/p\>/, '')
    end

    if text =~ /\<strong\>/
      text = text.split("\n")
      i = text.index{|e| e =~ /\<strong\>/ } + 1
      text = text[i..-1].join("\n")
    end

    text.gsub(/<pre>(.+?)<\/pre>/m) do
      code = $1.sub(/^\s*\n/, '')
      indent = code.gsub(/\n[ \t]*\n/, "\n").scan(/^ */).map{ |i| i.size }.min
      code.gsub!(/^#{' ' * indent}/, '') if indent > 0
      "#{code}"
    end
  end

  def generate_container_for(text, type, element)
    @type = type
    @selection = text.gsub("\n", '{{{{{this_is_a_new_line}}}}}')
    @selection = @selection.scan(%r{<#{type}>.*</#{type}\>})
    @selection = @selection.is_a?(Array) ? @selection[0] : @selection

    @selection.gsub!(%r{<#{type}>|</#{type}>}, '')
    @selection.gsub!('#', '')
    @selection.gsub!('{{{{{this_is_a_new_line}}}}}', "\n")
    @selection.gsub!(%r{\n\ *\n\ *}, "\n\n")
    @selection.gsub!(/\ {6}/, '')


    sanitize_title!
    "<#{element} class='#{type}-container'>#{@selection}</#{element}>"
  end

  def is_documented?(method)
    (method.text =~ regex_tag_scanner).nil? ? false : true
  end

  def regex_tag_scanner
    %r{<description>.*</description\>|<route>.*</route\>|<response>.*</response\>|<request>.*</request\>}
  end

  def has_request_body?(method)
    (method.text =~ %r{<request>.*</request\>}).nil? ? false : true
  end

  def sanitize_title!
    return unless @selection =~ /\#/

    i = @selection.index{|e| e =~ /(\#)(?=\ \w)/ } + 1
    @selection = @selection[i..-1]
  end

  # probably should bring in nokogiri/libxml2 to do this right.. not sure if
  # it's worth it.
  def frame_link(content)
    content.gsub(%r!<a href="http://[^>]*>!).each do |tag|
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
    CGI::escapeHTML(html)
  end

  # XXX may my sins be not visited upon my sons.
  def render_class_tree(entries, parent=nil)
    namespaces = { }

    entries.sort.inject('') do |out, klass|
      unless namespaces[klass.full_name]
        if parent
          text = '<span class="parent">%s::</span>%s' % [parent.full_name, klass.name]
        else
          text = klass.name
        end

        if klass.document_self
          out << '<li>'
          out << link_to(text, classfile(klass))
        end

        subentries = @classes.select { |x| x.full_name[/^#{klass.full_name}::/] }
        subentries.each { |x| namespaces[x.full_name] = true }
        out << "\n<ol>" + render_class_tree(subentries, klass) + "\n</ol>"

        if klass.document_self
          out << '</li>'
        end
      end

      out
    end
  end
    
  def build_javascript_search_index(entries)
    result = "var search_index = [\n"
    entries.each do |entry|
      method_name = entry.name
      module_name = entry.parent_name
      # FIXME link
      html = link_to_method(entry, [classfile(entry.parent), (entry.aref rescue "method-#{entry.html_name}")].join('#'))
      result << "  { method: '#{method_name.downcase}', " +
                      "module: '#{module_name.downcase}', " +
                      "html: '#{html}' },\n"
    end
    result << ']'
    result
  end

  def link_to(text, url = nil, classname = nil)
    class_attr = classname ? ' class="%s"' % classname : ''

    if url
        %[<a href="#{url}"#{class_attr}>#{text}</a>]
    elsif classname
        %[<span#{class_attr}>#{text}</span>]
    else
      text
    end
  end

  # +method_text+ is in the form of "ago (ActiveSupport::TimeWithZone)".
  def link_to_method(entry, url = nil, classname = nil)
    method_name = entry.pretty_name rescue entry.name
    module_name = entry.parent_name rescue entry.name
    link_to %Q(<span class="method_name">#{h method_name}</span> <span class="module_name">(#{h module_name})</span>), url, classname
  end

  def classfile(klass)
    # FIXME sloooooooow
    Pathname.new(File.join(CLASS_DIR, klass.full_name.split('::')) + '.html')
  end

  def outjoin(name)
    File.join(@outputdir, name)
  end

  def templjoin(name)
    File.join(@templatedir, name)
  end

  def haml_file(file)
    Haml::Engine.new(File.read(file), :format => :html4)
  end
end 
