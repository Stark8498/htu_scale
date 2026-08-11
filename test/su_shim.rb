# frozen_string_literal: true

# Minimal SketchUp API shim — just enough to load HTU ScalePlus end to end on
# plain MRI and run create_menu, so that missing constants, bad require paths,
# NoMethodErrors at load time and dropped decompiler nodes surface as failures
# instead of waiting for a real SketchUp session.
#
# This is a LOAD harness, not a behaviour harness: methods return plausible
# shapes, they do not model SketchUp semantics.

$SU_CALLS = Hash.new { |h, k| h[k] = [] }
$SU_TIMERS = []

module Sketchup
  class Entity; end
  class Drawingelement < Entity; end
  class ComponentDefinition < Drawingelement; end
  class ComponentInstance < Drawingelement; end
  class Group < Drawingelement; end
  class Color
    attr_accessor :red, :green, :blue, :alpha
    def initialize(r = 0, g = 0, b = 0, a = 255)
      if r.is_a?(Array)
        @red, @green, @blue, @alpha = r[0].to_i, r[1].to_i, r[2].to_i, (r[3] || 255).to_i
      elsif r.is_a?(String)
        @red = @green = @blue = 0
        @alpha = 255
      else
        @red, @green, @blue, @alpha = r.to_i, g.to_i, b.to_i, a.to_i
      end
    end
    def to_a; [@red, @green, @blue, @alpha]; end
    def to_i; (@red << 16) | (@green << 8) | @blue; end
    def blend(_other, _weight); self; end
  end
  class ImageRep; def initialize(*); end; end
  class InstancePath; def initialize(*); end; end
  class InputPoint; def initialize(*); end; end
  class Http; end

  class Overlay
    attr_accessor :name, :description
    def initialize(*); end
    def enabled?; false; end
    def start_observing_model; end
    def stop_observing_model; end
  end

  class AppObserver; end
  class SelectionObserver; end
  class ToolsObserver; end

  class Selection
    include Enumerable
    def each(&b); [].each(&b); end
    def [](_i); nil; end
    def size; 0; end
    def empty?; true; end
  end

  class Overlays
    def find(&b); nil; end
    def add(_o); true; end
    def remove(_o); true; end
    def each(&b); [].each(&b); end
  end

  class Model
    def selection; @selection ||= Selection.new; end
    def overlays; @overlays ||= Overlays.new; end
    def active_view; @view ||= View.new; end
    def entities; []; end
    def materials; []; end
    def pages; []; end
    def add_observer(*); true; end
    def start_operation(*); true; end
    def commit_operation; true; end
    def abort_operation; true; end
    def options; Hash.new { |h, k| h[k] = {} }; end
  end

  class Camera
    def eye; Geom::Point3d.new(100, 100, 100); end
    def target; ORIGIN; end
    def up; Z_AXIS; end
    def direction; Geom::Vector3d.new(-1, -1, -1).normalize; end
    def xaxis; X_AXIS; end
    def yaxis; Y_AXIS; end
    def zaxis; Z_AXIS; end
    def perspective?; true; end
    def fov; 35.0; end
    def height; 100.0; end
  end

  class View
    attr_reader :model
    def initialize(model = nil); @model = model; @textures = 0; end
    def invalidate; self; end
    def refresh; self; end
    def vpwidth; 1000; end
    def vpheight; 800; end
    def camera; @camera ||= Camera.new; end
    def add_observer(*); true; end
    def remove_observer(*); true; end
    def screen_coords(_pt); Geom::Point3d.new; end
    def pixels_to_model(px, _pt); px.to_f; end
    def inference_locked?; false; end
    def lock_inference(*); self; end
    def tooltip=(_t); _t; end
    def line_width=(_w); _w; end
    def line_stipple=(_s); _s; end
    def drawing_color=(_c); _c; end
    def draw(*); self; end
    def draw2d(*); self; end
    def draw_points(*); self; end
    def draw_text(*); self; end
    def draw_polyline(*); self; end
    def drawing_color; Sketchup::Color.new(0, 0, 0); end
    def set_color_from_line(*); self; end
    # Real signature: text_bounds(point, text, options = {}) -> Geom::Bounds2d
    def text_bounds(point, text, options = {})
      size = (options[:size] || 10).to_f
      w = text.to_s.length * size * 0.6
      Geom::Bounds2d.new(point[0], point[1], w, size * 1.3)
    end
    def load_texture(_rep); @textures += 1; end
    def release_texture(_id); true; end
    def guess_target; ORIGIN; end
    def write_image(*); true; end
  end

  class << self
    def platform; :platform_win; end
    def version; "26.0.0"; end
    def active_model; @model ||= Model.new; end
    def read_default(_sec, _key, default = nil); default; end
    def write_default(_sec, _key, _val); true; end
    def send_action(a); $SU_CALLS[:send_action] << a; true; end
    def set_status_text(*); true; end
    def status_text=(_t); true; end
    def format_length(l); l.to_s; end
    def temp_dir; Dir.tmpdir; end
    def focus; true; end
    def add_observer(o); $SU_CALLS[:app_observer] << o; true; end
    def install_from_archive(*); true; end
    def extensions; @extensions ||= {}; end
    def register_extension(ex, _load = true)
      $SU_CALLS[:register_extension] << ex
      extensions[ex.name] = ex
      true
    end

    # SketchUp's loader: takes an extension-less path, tries .rbe/.rbs then .rb.
    # Returns false (does NOT raise) when nothing is found — dead requires such
    # as radial_menu/viewui/ui.rb's button/checkbox/toggle rely on this.
    def require(path)
      file = path.end_with?(".rb") ? path : "#{path}.rb"
      return false unless File.exist?(file)

      Kernel.require(File.expand_path(file))
    end
  end
end

class SketchupExtension
  attr_accessor :version, :copyright, :creator, :description
  attr_reader :name, :path

  def initialize(name, path)
    @name = name
    @path = path
    @loaded = false
  end

  def load_on_start?; true; end
  def uncheck; $SU_CALLS[:uncheck] << @name; true; end
  def check; true; end
  def loaded?; @loaded; end

  def load_extension
    file = @path.end_with?(".rb") ? @path : "#{@path}.rb"
    Kernel.require(File.expand_path(file))
    @loaded = true
  end
end

module UI
  MENUS = Hash.new { |h, k| h[k] = Menu.new(k) }

  class Menu
    attr_reader :name, :items, :submenus
    def initialize(name); @name = name; @items = []; @submenus = {}; end
    def add_item(label = nil, &blk)
      @items << (label.respond_to?(:menu_text) ? label.menu_text : label)
      $SU_CALLS[:menu_item] << [@name, @items.last]
      blk
    end
    def add_submenu(name)
      @submenus[name] ||= Menu.new("#{@name}/#{name}")
    end
    def add_separator; true; end
    def set_validation_proc(&b); b; end
  end

  class Command
    attr_accessor :small_icon, :large_icon, :tooltip, :status_bar_text, :menu_text
    attr_reader :proc
    def initialize(text, &blk)
      @menu_text = text
      @proc = blk
      $SU_CALLS[:command] << text
    end
    def set_validation_proc(&b); @validation = b; self; end
    def get_validation_proc; @validation; end
    def validate; @validation && @validation.call; end
    def extension; nil; end
    def extension=(_e); _e; end
  end

  class Toolbar
    attr_reader :name, :items
    def initialize(name); @name = name; @items = []; $SU_CALLS[:toolbar] << name; end
    def add_item(cmd); @items << cmd; self; end
    def add_separator; self; end
    def restore; $SU_CALLS[:toolbar_restore] << @name; self; end
    def show; self; end
    def get_last_state; 1; end
  end

  class HtmlDialog
    attr_reader :options, :callbacks
    def initialize(opts = {}); @options = opts; @callbacks = {}; end
    def add_action_callback(name, &blk); @callbacks[name] = blk; self; end
    def set_html(_h); self; end
    def set_file(f); @file = f; $SU_CALLS[:dialog_file] << f; self; end
    def set_url(_u); self; end
    def execute_script(_s); self; end
    def show; @visible = true; self; end
    def close; @visible = false; self; end
    def visible?; !!@visible; end
    def bring_to_front; self; end
    def center; self; end
  end

  class << self
    def menu(name); MENUS[name]; end
    def scale_factor; 1.0; end
    def messagebox(msg, *); $SU_CALLS[:messagebox] << msg; 1; end
    def inputbox(*); nil; end
    def openURL(url); $SU_CALLS[:open_url] << url; true; end
    def openpanel(*); nil; end
    def savepanel(*); nil; end
    def beep; true; end
    def start_timer(sec, repeat = false, &blk)
      id = $SU_TIMERS.size
      $SU_TIMERS << { id: id, sec: sec, repeat: repeat, proc: blk }
      id
    end
    def stop_timer(_id); true; end
    def show_extension_manager; true; end
  end
end

module Geom
  class Point3d
    attr_accessor :x, :y, :z
    def initialize(x = 0, y = 0, z = 0)
      x, y, z = x if x.is_a?(Array)
      @x = x.to_f; @y = (y || 0).to_f; @z = (z || 0).to_f
    end
    def to_a; [@x, @y, @z]; end
    def [](i); to_a[i]; end
    def []=(i, v); [:@x, :@y, :@z].each_with_index { |s, j| instance_variable_set(s, v.to_f) if j == i }; v; end
    def clone; self.class.new(@x, @y, @z); end
    def to_s; "(#{@x}, #{@y}, #{@z})"; end
    def ==(other); other.respond_to?(:to_a) && to_a == other.to_a[0, 3]; end
    def +(o); self.class.new(@x + o[0], @y + o[1], @z + o[2]); end
    def -(o); Vector3d.new(@x - o[0], @y - o[1], @z - o[2]); end
    def distance(o); Math.sqrt((@x - o[0])**2 + (@y - o[1])**2 + (@z - o[2])**2); end
    def vector_to(o); Vector3d.new(o[0] - @x, o[1] - @y, o[2] - @z); end
    def offset(vec, len = 1); self.class.new(@x + vec[0] * len, @y + vec[1] * len, @z + vec[2] * len); end
    def offset!(vec, len = 1); @x += vec[0] * len; @y += vec[1] * len; @z += vec[2] * len; self; end
    def transform(_t); clone; end
    def transform!(_t); self; end
    def project_to_line(*); clone; end
    def project_to_plane(*); clone; end
    def on_plane?(*); false; end
    def on_line?(*); false; end
  end

  class Vector3d < Point3d
    def length; Math.sqrt(@x**2 + @y**2 + @z**2); end
    def length=(l); n = length; return l if n.zero?; k = l / n; @x *= k; @y *= k; @z *= k; l; end
    def normalize; n = length; n.zero? ? clone : Vector3d.new(@x / n, @y / n, @z / n); end
    def normalize!; n = length; unless n.zero?; @x /= n; @y /= n; @z /= n; end; self; end
    def valid?; length > 0; end
    def reverse; Vector3d.new(-@x, -@y, -@z); end
    def reverse!; @x = -@x; @y = -@y; @z = -@z; self; end
    def dot(o); @x * o[0] + @y * o[1] + @z * o[2]; end
    def cross(o)
      Vector3d.new(@y * o[2] - @z * o[1], @z * o[0] - @x * o[2], @x * o[1] - @y * o[0])
    end
    def %(o); dot(o); end
    def *(o); o.is_a?(Numeric) ? Vector3d.new(@x * o, @y * o, @z * o) : cross(o); end
    def parallel?(o); cross(o).length < 1e-10; end
    def perpendicular?(o); dot(o).abs < 1e-10; end
    def samedirection?(o); parallel?(o) && dot(o) > 0; end
    def angle_between(o)
      d = normalize.dot(o.is_a?(Vector3d) ? o.normalize : Vector3d.new(o.to_a).normalize)
      Math.acos([[d, 1.0].min, -1.0].max)
    end
  end

  class Point2d
    attr_accessor :x, :y
    def initialize(x = 0, y = 0)
      x, y = x if x.is_a?(Array)
      @x = x.to_f; @y = (y || 0).to_f
    end
    def to_a; [@x, @y]; end
    def [](i); to_a[i]; end
    def clone; Point2d.new(@x, @y); end
  end

  class Vector2d < Point2d
    def length; Math.sqrt(@x**2 + @y**2); end
  end

  class Bounds2d
    attr_reader :upper_left, :lower_right
    # Real signatures: (Point2d, Point2d) | (x, y, width, height) | (Bounds2d)
    def initialize(*args)
      case args.size
      when 1
        @upper_left  = args[0].upper_left
        @lower_right = args[0].lower_right
      when 2
        @upper_left  = Point2d.new(args[0].to_a)
        @lower_right = Point2d.new(args[1].to_a)
      when 4
        @upper_left  = Point2d.new(args[0], args[1])
        @lower_right = Point2d.new(args[0] + args[2], args[1] + args[3])
      else
        @upper_left  = Point2d.new
        @lower_right = Point2d.new
      end
    end
    def width; (@lower_right.x - @upper_left.x).abs; end
    def height; (@lower_right.y - @upper_left.y).abs; end
    def center; Point2d.new((@upper_left.x + @lower_right.x) / 2.0, (@upper_left.y + @lower_right.y) / 2.0); end
    def contains?(*); false; end
    def to_a; [@upper_left, @lower_right]; end
  end

  class BoundingBox
    def initialize(*); end
    def add(*); self; end
    def center; Point3d.new; end
    def min; Point3d.new; end
    def max; Point3d.new; end
    def width; 0; end
    def height; 0; end
    def depth; 0; end
    def empty?; true; end
    def valid?; false; end
    def diagonal; 0; end
    def contains?(*); false; end
    def intersect(*); BoundingBox.new; end
    def clear; self; end
    def corner(_i); Point3d.new; end
  end

  class Transformation
    def initialize(*); end
    def self.scaling(*); new; end
    def self.translation(*); new; end
    def self.rotation(*); new; end
    def to_a; Array.new(16, 0.0); end
    def *(_o); self; end
    def inverse; self; end
  end

  def self.intersect_line_plane(*); Point3d.new; end
  def self.linear_combination(*); Point3d.new; end
end

class Length < Float
  def to_l; self; end
  def to_s; super; end
end

class Numeric
  def to_l; Length.new(to_f); end unless method_defined?(:to_l)
  def inch; self; end unless method_defined?(:inch)
  def m; self * 39.3701; end unless method_defined?(:m)
  def mm; self / 25.4; end unless method_defined?(:mm)
  def cm; self / 2.54; end unless method_defined?(:cm)
  def feet; self * 12; end unless method_defined?(:feet)
  def degrees; self * Math::PI / 180; end unless method_defined?(:degrees)
  def radians; self * 180 / Math::PI; end unless method_defined?(:radians)
end

class String
  def to_l; Length.new(to_f); end unless method_defined?(:to_l)
end

# SketchUp's global geometry constants.
ORIGIN   = Geom::Point3d.new(0, 0, 0)
X_AXIS   = Geom::Vector3d.new(1, 0, 0)
Y_AXIS   = Geom::Vector3d.new(0, 1, 0)
Z_AXIS   = Geom::Vector3d.new(0, 0, 1)
IDENTITY = Geom::Transformation.new

# View#draw primitive modes.
GL_POINTS      = 0
GL_LINES       = 1
GL_LINE_STRIP  = 2
GL_LINE_LOOP   = 3
GL_TRIANGLES   = 4
GL_TRIANGLE_STRIP = 5
GL_TRIANGLE_FAN   = 6
GL_QUADS       = 7
GL_QUAD_STRIP  = 8
GL_POLYGON     = 9

# View#draw_text option constants.
TextAlignLeft   = 0
TextAlignCenter = 1
TextAlignRight  = 2
TextVerticalAlignBaseline   = 0
TextVerticalAlignCapHeight  = 1
TextVerticalAlignCenter     = 2
TextVerticalAlignBoundsTop  = 3

MF_ENABLED   = 0
MF_DISABLED  = 1
MF_CHECKED   = 2
MF_UNCHECKED = 3
MF_GRAYED    = 4

# ------------------------------------------------- sketchup.rb / extensions.rb
$LOADED_FILE_MARKERS = {}

def file_loaded?(file); $LOADED_FILE_MARKERS.key?(file); end
def file_loaded(file); $LOADED_FILE_MARKERS[file] = true; end

# Satisfy `require 'sketchup.rb'` / `require 'extensions.rb'` from plugin files.
$LOADED_FEATURES << "sketchup.rb" << "extensions.rb"
module Kernel
  alias_method :__orig_require, :require
  def require(name)
    return true if %w[sketchup.rb extensions.rb langhandler.rb].include?(name)

    __orig_require(name)
  end
end

require "tmpdir"
