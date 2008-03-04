#!/usr/bin/env ruby

require 'test/unit'
require 'rubygems'
require 'action_pack'

if path = $:.detect {|p| p =~ %r{actionpack-[\d.]+/lib$} }
  $:.unshift(path + '/action_controller/vendor/html-scanner')
end

require 'active_support'
require 'action_view'
require File.dirname(__FILE__) + '/../../lib/haml'
require 'haml/template'
require File.dirname(__FILE__) + '/mocks/article'

module TestFilter
  include Haml::Filters::Base

  def render(text)
    "TESTING HAHAHAHA!"
  end
end

class TemplateTest < Test::Unit::TestCase
  @@templates = %w{       very_basic        standard    helpers
    whitespace_handling   original_engine   list        helpful
    silent_script         tag_parsing       just_stuff  partials
    filters }

  def setup
    Haml::Template.options = { :filters => { 'test'=>TestFilter } }
    @base = ActionView::Base.new(File.dirname(__FILE__) + "/templates/", {'article' => Article.new, 'foo' => 'value one'})
    @base.send(:evaluate_assigns)

    # This is used by form_for.
    # It's usually provided by ActionController::Base.
    def @base.protect_against_forgery?; false; end
  end

  def render(text)
    Haml::Engine.new(text).to_html(@base)
  end

  def load_result(name)
    @result = ''
    File.new(File.dirname(__FILE__) + "/results/#{name}.xhtml").each_line { |l| @result += l }
    @result
  end

  def assert_renders_correctly(name, &render_method)
    render_method ||= proc { |name| @base.render(name) }
    test = Proc.new do |rendered|
      load_result(name).split("\n").zip(rendered.split("\n")).each_with_index do |pair, line|
        message = "template: #{name}\nline:     #{line}"
        assert_equal(pair.first, pair.last, message)
      end
    end
    begin
      test.call(render_method[name])
    rescue ActionView::TemplateError => e
      if e.message =~ /Can't run [\w:]+ filter; required (one of|file) ((?:'\w+'(?: or )?)+)(, but none were found| not found)/
        puts "\nCouldn't require #{$2}; skipping a test."
      else
        raise e
      end
    end
  end

  def test_empty_render_should_remain_empty
    assert_equal('', render(''))
  end

  def test_templates_should_render_correctly
    @@templates.each do |template|
      assert_renders_correctly template
    end
  end

  def test_templates_should_render_correctly_with_render_proc
    @@templates.each do |template|
      assert_renders_correctly(template) do |name|
        engine = Haml::Engine.new(File.read(File.dirname(__FILE__) + "/templates/#{name}.haml"), :filters => { 'test'=>TestFilter })
        engine.render_proc(@base).call
      end
    end
  end

  def test_templates_should_render_correctly_with_def_method
    @@templates.each do |template|
      assert_renders_correctly(template) do |name|
        method = "render_haml_" + name.gsub(/[^a-zA-Z0-9]/, '_')

        engine = Haml::Engine.new(File.read(File.dirname(__FILE__) + "/templates/#{name}.haml"), :filters => { 'test'=>TestFilter })
        engine.def_method(@base, method)
        @base.send(method)
      end
    end
  end

  def test_action_view_templates_render_correctly
    @base.instance_variable_set("@content_for_layout", 'Lorem ipsum dolor sit amet')
    assert_renders_correctly 'content_for_layout'
  end

  def test_instance_variables_should_work_inside_templates
    @base.instance_variable_set("@content_for_layout", 'something')
    assert_equal("<p>something</p>", render("%p= @content_for_layout").chomp)

    @base.instance_eval("@author = 'Hampton Catlin'")
    assert_equal("<div class='author'>Hampton Catlin</div>", render(".author= @author").chomp)

    @base.instance_eval("@author = 'Hampton'")
    assert_equal("Hampton", render("= @author").chomp)

    @base.instance_eval("@author = 'Catlin'")
    assert_equal("Catlin", render("= @author").chomp)
  end

  def test_instance_variables_should_work_inside_attributes
    @base.instance_eval("@author = 'hcatlin'")
    assert_equal("<p class='hcatlin'>foo</p>", render("%p{:class => @author} foo").chomp)
  end

  def test_template_renders_should_eval
    assert_equal("2\n", render("= 1+1"))
  end

  def test_rhtml_still_renders
    # Make sure it renders normally
    res = @base.render("../rhtml/standard")
    assert !(res.nil? || res.empty?)

    # Register Haml stuff in @base...
    @base.render("standard") 

    # Does it still render?
    res = @base.render("../rhtml/standard")
    assert !(res.nil? || res.empty?)
  end

  def test_haml_options
    Haml::Template.options = { :suppress_eval => true }
    assert_equal({ :suppress_eval => true }, Haml::Template.options)
    assert_renders_correctly("eval_suppressed")
    Haml::Template.options = {}
  end

  def test_exceptions_should_work_correctly
    begin
      render("- raise 'oops!'")
    rescue Exception => e
      assert_equal("oops!", e.message)
      assert_match(/^\(haml\):1/, e.backtrace[0])
    else
      assert false
    end

    template = <<END
%p
  %h1 Hello!
  = "lots of lines"
  = "even more!"
  - raise 'oh no!'
  %p
    this is after the exception
    %strong yes it is!
ho ho ho.
END

    begin
      render(template.chomp)
    rescue Exception => e
      assert_match(/^\(haml\):5/, e.backtrace[0])
    else
      assert false
    end
  end  
end
