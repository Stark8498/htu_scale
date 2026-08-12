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
  class Entity
    # Attribute dictionaries, modelled well enough for DimFavorites: values
    # round-trip per (dictionary, key) and a missing key returns the default.
    def attributes; @attributes ||= Hash.new { |h, k| h[k] = {} }; end
    def set_attribute(dict, key, value); attributes[dict.to_s][key] = value; end
    def get_attribute(dict, key, default = nil)
      attributes[dict.to_s].fetch(key, default)
    end
    # Every real entity answers this, and it is never decoration: an undo or an
    # explode can delete one while plugin code still holds the reference, which
    # is exactly the situation GroupLock has to survive. A shim where valid? did
    # not exist raised NoMethodError on the guard clauses written to handle it.
    def valid?; !@deleted; end
    # Which collection holds this entity, so explode can put children back where
    # the group was. The real API exposes #parent (a definition) rather than the
    # collection; this is shim plumbing, kept under a name no SketchUp method
    # has, so nothing can mistake it for API surface being tested.
    attr_accessor :parent_entities
    def mark_deleted!; @deleted = true; self; end
  end
  class Drawingelement < Entity; end
  # A definition's behavior carries the no-scale mask the tool reads to know
  # which handles a component allows. 0 means "everything is scalable", which
  # is the plain case and the one worth defaulting to.
  class Behavior
    attr_accessor :mask
    def initialize; @mask = 0; end
    def no_scale_mask?; @mask; end
    def no_scale_mask=(m); @mask = m; end
  end
  class ComponentDefinition < Drawingelement
    def behavior; @behavior ||= Behavior.new; end
    def bounds; @bounds ||= Geom::BoundingBox.new; end
    def entities; @entities ||= Entities.new; end
  end
  class ComponentInstance < Drawingelement
    # A real instance always resolves to a definition; DimFavorites writes to both.
    def definition; @definition ||= ComponentDefinition.new; end
  end
  # Bounds and placement, so a selected object can be measured. Without these
  # anything that reaches compute_selected_bounds dies, which is every code path
  # that runs with something actually selected.
  module Placed
    def transformation; @transformation ||= Geom::Transformation.new; end
    def transformation=(t); @transformation = t; end
    def local_bounds; @local_bounds ||= Geom::BoundingBox.new; end
    def bounds; local_bounds; end
  end
  class ComponentInstance; include Placed; end
  class Group < Drawingelement
    include Placed
    def definition; @definition ||= ComponentDefinition.new; end
    # The same collection the definition holds, as in the real API, so a mask set
    # through the definition and children read through the group cannot drift.
    def entities; definition.entities; end
    # Puts the children back into the collection the group itself was in and
    # takes the group out of the model, the way the real one does -- including
    # the return value, which is the only dependable handle on the children
    # afterwards and the thing GroupLock#explode_wrapper relies on.
    def explode
      parent = parent_entities
      children = entities.to_a
      children.each do |child|
        entities.remove_entity(child)
        parent.add_entity(child) if parent
      end
      parent.remove_entity(self) if parent
      mark_deleted!
      $SU_CALLS[:explode] << self
      children
    end
  end

  # Real Entities, not the empty array this used to be. The multi-object axis
  # lock adds a group, reads it back out of the collection and explodes it, so a
  # collection that cannot hold anything cannot test any of it.
  class Entities
    include Enumerable
    def initialize(*); @items = []; end
    def each(&b); @items.each(&b); end
    def [](i); @items[i]; end
    def size; @items.size; end
    def length; @items.size; end
    def empty?; @items.empty?; end
    def to_a; @items.dup; end
    # SketchUp MOVES the listed entities into the new group rather than copying
    # them. A shim that left them in place would hide a double-membership bug.
    def add_group(*objects)
      objects = objects.flatten
      group = Group.new
      objects.each { |e| @items.delete(e) }
      objects.each { |e| group.entities.add_entity(e) }
      add_entity(group)
      $SU_CALLS[:add_group] << objects
      group
    end
    def add_entity(e); @items << e unless @items.include?(e); e.parent_entities = self; e; end
    def remove_entity(e); @items.delete(e); e.parent_entities = nil if e.parent_entities.equal?(self); e; end
    def transform_entities(*); $SU_CALLS[:transform_entities] << true; true; end
  end
  # Present so "is this a scale target?" can be answered in a test. The tool
  # accepts only things that respond to #definition, and raw geometry does not.
  class Face < Drawingelement; end
  class Edge < Drawingelement; end
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
  # #pick is what the overlay calls on every mouse move it acts on, so a bare
  # InputPoint made the whole dispatch path untestable.
  class InputPoint
    def initialize(*); end
    def pick(_view, x, y, _ip = nil); @position = Geom::Point3d.new(x, y, 0); true; end
    def position; @position ||= Geom::Point3d.new; end
    def valid?; !@position.nil?; end
    def copy!(other); @position = other.position; self; end
    def draw(*); self; end
  end
  class Http; end

  class Overlay
    attr_accessor :name, :description
    def initialize(*); end
    # Registered disabled, the way SketchUp does it. The writer is the part that
    # was missing: observer.rb#add_overlay enables the overlay on registration and
    # that line only means anything if this exists -- without it the assignment
    # raised, the rescue around it swallowed the error, and every path in the
    # plugin gated on enabled? stayed unreachable from a test.
    def enabled?; @enabled ? true : false; end
    def enabled=(state); @enabled = state; end
    def valid?; true; end
    def start_observing_model; end
    def stop_observing_model; end
  end

  class AppObserver; end
  class SelectionObserver; end
  class ToolsObserver; end
  class ModelObserver; end
  class EntitiesObserver; end

  # Backed by a real array rather than always-empty: the tool reaches the
  # component it is editing through the selection, so a test that cannot select
  # anything cannot reach any of that code. Starts empty, as before.
  class Selection
    include Enumerable
    def initialize; @items = []; end
    def each(&b); @items.each(&b); end
    def [](i); @items[i]; end
    def size; @items.size; end
    def length; @items.size; end
    def empty?; @items.empty?; end
    def clear; @items = []; self; end
    def add(*objs); @items |= objs.flatten; self; end
    def to_a; @items.dup; end
    # Distinct from #add: an observer added to the selection would otherwise
    # become a selected entity and be handed to the tool as the component.
    def add_observer(o); $SU_CALLS[:selection_observer] << o; true; end
  end

  class Overlays
    def find(&b); nil; end
    def add(_o); true; end
    def remove(_o); true; end
    def each(&b); [].each(&b); end
  end

  # The tool stack. Tool#active? consults it on every mouse move, so without it
  # nothing that goes through onMouseMove can be exercised at all.
  class Tools
    attr_reader :stack
    def initialize; @stack = []; end
    def active_tool; @stack.last; end
    # Writable, because "the user is mid-orbit" is not a state a test can reach by
    # pushing a Ruby tool -- SketchUp's camera tools are native and never appear on
    # the stack this shim models. The plugin asks this to decide whether it may
    # touch the stack at all, so a test has to be able to say yes.
    attr_writer :active_tool_name
    def active_tool_name
      return @active_tool_name if @active_tool_name
      top = @stack.last
      top.respond_to?(:tool_name) ? top.tool_name : "SelectionTool"
    end
    def push_tool(t); @stack.push(t); $SU_CALLS[:push_tool] << t; true; end
    def pop_tool; $SU_CALLS[:pop_tool] << @stack.last; @stack.pop; true; end
    def add_observer(o); $SU_CALLS[:tools_observer] << o; true; end
  end

  class Model
    def tools; @tools ||= Tools.new; end
    def select_tool(t); tools.stack.clear; tools.push_tool(t) if t; $SU_CALLS[:select_tool] << t; true; end
    def selection; @selection ||= Selection.new; end
    def overlays; @overlays ||= Overlays.new; end
    # Handed its model, the way a real view always knows one. Drawing code
    # reaches the selection through view.model, and a view with none turns that
    # into a NoMethodError the moment a test tries to draw anything.
    def active_view; @view ||= View.new(self); end
    def valid?; true; end
    def entities; @entities ||= Entities.new(self); end
    # No group-editing context in the shim, so the active context IS the root.
    # Real SketchUp returns a group's or component's entities while the user is
    # inside one, which is why GroupLock#contexts looks at both and dedupes.
    def active_entities; entities; end
    def materials; []; end
    def pages; []; end
    def definitions; @definitions ||= []; end
    def add_observer(o); $SU_CALLS[:model_observer] << o; true; end
    # Recorded: applying the scale mode runs on every selection change, and
    # "did it open an operation it did not need?" is the difference between a
    # quiet no-op and dirtying the file on every click.
    def start_operation(name = nil, *); $SU_CALLS[:start_operation] << name; true; end
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

  # What a click lands on. Tests set #picked; do_pick records so a test can
  # tell "asked the model" from "guessed".
  class PickHelper
    attr_accessor :picked
    def do_pick(x, y); $SU_CALLS[:do_pick] << [x, y]; picked ? 1 : 0; end
    def best_picked; @picked; end
    def count; @picked ? 1 : 0; end
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
    # A flat projection rather than the origin for everything. Retargeting asks
    # where the selection lands on screen, and a view that maps the whole model
    # onto one point cannot answer that -- it would report every click as being
    # on the grips.
    # A plain [x, y, z] is as good as a Point3d here, the way it is everywhere
    # else in the API -- create_box hands out raw arrays and they arrive here
    # unconverted.
    def screen_coords(pt)
      pt = Geom::Point3d.new(*pt) if pt.is_a?(Array)
      Geom::Point3d.new(pt.x, pt.y, 0)
    end
    def pick_helper(*); @pick_helper ||= PickHelper.new; end
    def pixels_to_model(px, _pt); px.to_f; end
    def inference_locked?; false; end
    def lock_inference(*); self; end
    def tooltip=(_t); _t; end
    def line_width=(_w); _w; end
    def line_stipple=(_s); _s; end
    # The colour is remembered rather than discarded, so a recorded draw call
    # carries the colour in force when it was made. Whether a shape is filled
    # or only outlined is otherwise invisible to a test.
    def drawing_color=(c); @drawing_color = c; end
    def draw(mode = nil, points = nil, *)
      $SU_CALLS[:draw] << [mode, points, @drawing_color]
      self
    end
    def draw2d(mode = nil, points = nil, *)
      $SU_CALLS[:draw2d] << [mode, points, @drawing_color]
      self
    end
    def draw_points(*); self; end
    def draw_text(point = nil, text = nil, options = {}, *)
      check_text_options!(options)
      $SU_CALLS[:draw_text] << [point, text, options]
      self
    end
    def draw_polyline(*); self; end
    def drawing_color; @drawing_color || Sketchup::Color.new(0, 0, 0); end
    def set_color_from_line(*); self; end
    # SketchUp validates the options hash and raises
    #   TypeError: wrong argument type nil (expected Symbol)
    # on any non-Symbol key. Modelled here so a malformed options hash fails the
    # harness instead of sailing through it (this is how the {nil => options}
    # tooltip defect stayed invisible while every gate reported PASS).
    def check_text_options!(options)
      return unless options.is_a?(Hash)

      bad = options.keys.reject { |k| k.is_a?(Symbol) }
      return if bad.empty?

      raise TypeError, "wrong argument type #{bad.first.class} (expected Symbol)"
    end

    # Real signature: text_bounds(point, text, options = {}) -> Geom::Bounds2d
    def text_bounds(point, text, options = {})
      check_text_options!(options)
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
    # Real read_default/write_default persist to the registry (or plist) and
    # survive restarts. Modelled with a store rather than returning the default,
    # so code that clobbers a saved preference on load is visible to the tests.
    def defaults; @defaults ||= {}; end
    def read_default(sec, key, default = nil)
      defaults.fetch([sec.to_s, key.to_s], default)
    end

    def write_default(sec, key, val)
      defaults[[sec.to_s, key.to_s]] = val
      true
    end
    def send_action(a); $SU_CALLS[:send_action] << a; true; end
    # Recorded, not swallowed: the VCB label, value and prompt are the only
    # feedback the in-place dimension editor gives about what it is waiting for.
    def set_status_text(text = "", target = nil)
      $SU_CALLS[:status_text] << [text, target]
      true
    end
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
    def add_item(cmd)
      @items << cmd
      $SU_CALLS[:toolbar_item] << [@name, cmd.respond_to?(:menu_text) ? cmd.menu_text : cmd]
      self
    end
    def add_separator; self; end
    def restore; $SU_CALLS[:toolbar_restore] << @name; self; end
    def show; self; end
    def get_last_state; 1; end
  end

  class HtmlDialog
    attr_reader :options, :callbacks
    def initialize(opts = {}); @options = opts; @callbacks = {}; end
    def add_action_callback(name, &blk); @callbacks[name] = blk; self; end
    # Recorded rather than dropped: the Add window's whole output is the
    # render(...) call it pushes, so a test can only see it through these.
    attr_reader :html, :scripts
    def set_html(h); @html = h; self; end
    def set_file(f); @file = f; $SU_CALLS[:dialog_file] << f; self; end
    def set_url(_u); self; end
    def execute_script(s); (@scripts ||= []) << s; self; end
    def show; @visible = true; self; end
    def close; @visible = false; self; end
    def visible?; !!@visible; end
    def bring_to_front; self; end
    def center; self; end
  end

  class << self
    def menu(name); MENUS[name]; end
    def scale_factor; 1.0; end
    # $SU_ANSWER lets a test say what the user clicked. Defaults to IDYES so a
    # confirmation that is never answered does not silently look like a refusal.
    def messagebox(msg, *); $SU_CALLS[:messagebox] << msg; $SU_ANSWER || IDYES; end
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
    # Recorded: a repeating timer that is never stopped keeps firing for the
    # rest of the SketchUp session, so "was it stopped" is worth being able to
    # assert on.
    def stop_timer(id); $SU_CALLS[:stop_timer] << id; true; end
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
    def self.axes(*); new; end
    def to_a; Array.new(16, 0.0); end
    def *(_o); self; end
    def inverse; self; end
    # Identity axes. dim_axis compares a dimension's direction against these to
    # decide which length it is, so a transformation without them cannot answer
    # the one question the whole context menu is keyed on.
    def origin; Point3d.new(0, 0, 0); end
    def xaxis; Vector3d.new(1, 0, 0); end
    def yaxis; Vector3d.new(0, 1, 0); end
    def zaxis; Vector3d.new(0, 0, 1); end
  end

  def self.intersect_line_plane(*); Point3d.new; end
  def self.linear_combination(*); Point3d.new; end
end

# In SketchUp a Length is a Float subclass. Plain Ruby cannot instantiate one --
# Float has no allocator, so `Length.new` raises -- and the shim used to call it
# from every to_l. The class stays defined because utils.rb tests
# `value.is_a?(Length)`, but to_l hands back an ordinary Float: arithmetic,
# comparison, sorting, to_f and to_s all behave the same, which is everything the
# plugin does with a length.
class Length < Float; end

class Numeric
  def to_l; to_f; end unless method_defined?(:to_l)
  def inch; self; end unless method_defined?(:inch)
  def m; self * 39.3701; end unless method_defined?(:m)
  def mm; self / 25.4; end unless method_defined?(:mm)
  def cm; self / 2.54; end unless method_defined?(:cm)
  def feet; self * 12; end unless method_defined?(:feet)
  def degrees; self * Math::PI / 180; end unless method_defined?(:degrees)
  def radians; self * 180 / Math::PI; end unless method_defined?(:radians)
end

class String
  # SketchUp parses the string in the model's current units and raises
  # ArgumentError on anything it cannot read. Modelled here (metric/mm) because
  # DimFavorites.parse relies on the raise to separate good input from bad --
  # a permissive to_f would silently turn "abc" into 0 and hide the bug.
  # The sign must be inside the capture, or "-5" parses as 5.
  LENGTH_PATTERN = /\A([+-]?(?:\d+(?:\.\d+)?|\.\d+))\s*(mm|cm|m|in|"|'|)\z/.freeze
  UNIT_SCALE = { "mm" => 1 / 25.4, "cm" => 1 / 2.54, "m" => 39.3701,
                 "in" => 1.0, '"' => 1.0, "'" => 12.0 }.freeze

  def to_l
    match = LENGTH_PATTERN.match(strip)
    raise ArgumentError, "invalid length: #{inspect}" unless match

    unit = match[2].empty? ? "mm" : match[2]
    match[1].to_f * UNIT_SCALE.fetch(unit)
  end
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

# Sketchup.set_status_text targets.
SB_PROMPT    = 0
SB_VCB_LABEL = 1
SB_VCB_VALUE = 2

MF_ENABLED   = 0
MF_DISABLED  = 1
MF_CHECKED   = 2
MF_UNCHECKED = 3
MF_GRAYED    = 4

# UI.messagebox button sets and the codes it answers with.
MB_OK          = 0
MB_OKCANCEL    = 1
MB_ABORTRETRYIGNORE = 2
MB_YESNOCANCEL = 3
MB_YESNO       = 4
MB_RETRYCANCEL = 5
MB_MULTILINE   = 6

IDOK     = 1
IDCANCEL = 2
IDABORT  = 3
IDRETRY  = 4
IDIGNORE = 5
IDYES    = 6
IDNO     = 7

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
