module TRINH_VAN_PHUC::HTU_ScalePlus
  module LengthUtils
    def self.number_to_current_length(numner)
      st = Sketchup.format_length(numner)
      if st.include?("mm")
        len = numner.mm
      elsif st.include?("cm")
        len = numner.cm
      elsif st.include?("m")
        len = numner.m
      else
        len
      end
      len
    end
  end
  class Settings
    def initialize(section)
      @section = section
      @cache = {}
    end
    def [](key, default = nil)
      if @cache.key?(key)
        x = @cache[key]
      else
        begin
          x = Sketchup.read_default(@section, key.to_s, default)
        rescue SyntaxError
          puts("#<Setting> Error reading setting! - Returning default value.")
          puts("> #{@section.inspect} - #{key.to_s.inspect} (#{default.inspect})")
          x = default
        end
        if default.is_a?(Length)
          x = x.to_l
        end
        if x.is_a?(String) && default.is_a?(Symbol)
          x = x.intern
        end
        @cache[key] = x
        x
      end
    end
    def []=(key, value)
      @cache[key] = value
      if value.is_a?(Length)
        value = value.to_f
      end
      if value.is_a?(Symbol)
        value = value.to_s
      end
      Sketchup.write_default(@section, key.to_s, value)
      value
    end
    def set_default(key, default = nil)
      self[key, default]
    end
    def sub_section(sub_section)
      new("#{@section}\\#{sub_section}")
    end
  end
  module Utils
    def object?(object)
      unless object.is_a?(Sketchup::Group) || object.is_a?(Sketchup::ComponentInstance)
        return false
      end
      true
    end
    def leaf_object?(object)
      best_object?(object)
    end
    def best_object?(object)
      unless object?(object)
        return
      end
      object.definition.entities.find_all do |e|
  object?(e)
end.empty?
    end
    def geometry?(entity)
      entity.is_a?(Sketchup::Drawingelement) && !object?(entity)
    end
    def definition_paths(d)
      unless d.is_a?(Sketchup::ComponentDefinition)
        d = d.definition
      end
      paths = []
      get_path(paths, d)
      paths
    end
    def get_path(paths, d, path_d = [])
      d.instances.each do |i|
        path = path_d.clone
        path << i
        parent = i.parent
        if parent.is_a?(Sketchup::Model)
          end_path = path
          paths << end_path.reverse
        else
          get_path(paths, parent, path)
        end
      end
    end
    def get_pickhelper_transformation(ph, entity)
      (0...ph.count).each do |i|
        path = ph.path_at(i)
        unless path.include?(entity)
          next
        end
        return ph.transformation_at(i)
      end
      Geom::Transformation.new
    end
    def object_bounds(object)
      if object.is_a?(Sketchup::Group)
        object.local_bounds
      elsif object.is_a?(Sketchup::ComponentInstance)
        object.definition.bounds
      end
    end
    def bound_points(bound)
      if bound.width == 0
        [0, 2, 6, 4].map do |i|
          bound.corner(i)
        end
      elsif bound.height == 0
        [0, 1, 5, 4].map do |i|
          bound.corner(i)
        end
      elsif bound.depth == 0
        [0, 1, 3, 2].map do |i|
          bound.corner(i)
        end
      else
      end
      (0..7).map do |i|
        bound.corner(i)
      end
    end
    def bottom_bound_points(bb, tr_bb = IDENTITY)
      pts = bound_points(bb).map do |pt|
  pt.transform(tr_bb)
end
      [pts[0], pts[1], pts[3], pts[2]]
    end
    def bounds_lines(bb, tr_bb = IDENTITY)
      pts = bound_points(bb).map do |pt|
  pt.transform(tr_bb)
end
      lines = pts.length == 8 ? [[pts[0], pts[1]], [pts[1], pts[3]], [pts[2], pts[3]], [pts[0], pts[2]], [pts[0], pts[4]], [pts[1], pts[5]], [pts[2], pts[6]], [pts[3], pts[7]], [pts[4], pts[5]], [pts[5], pts[7]], [pts[6], pts[7]], [pts[4], pts[6]]] : [[pts[0], pts[1]], [pts[1], pts[2]], [pts[2], pts[3]], [pts[0], pts[3]]]
      lines
    end
    def bounds_center_lines(bb, tr_bb = IDENTITY)
      pts = bound_points(bb).map do |pt|
  pt.transform(tr_bb)
end
      lines = [[midpoint([pts[0], pts[6]]), midpoint([pts[1], pts[7]])], [midpoint([pts[0], pts[5]]), midpoint([pts[2], pts[7]])], [midpoint([pts[0], pts[3]]), midpoint([pts[4], pts[7]])]]
      lines
    end
    def bounds_centers(bb, tr_bb = IDENTITY)
      pts = bound_points(bb).map do |pt|
  pt.transform(tr_bb)
end
      lines = pts.length == 8 ? [[pts[0], pts[3]], [pts[0], pts[5]], [pts[0], pts[6]], [pts[4], pts[7]], [pts[2], pts[7]], [pts[1], pts[7]]] : [[pts[0], pts[3]]]
      lines.map do |l|
        midpoint(l)
      end
    end
    def midpoint(segment)
      Geom.linear_combination(0.5, segment.first, 0.5, segment.last)
    end
    def point_between?(a, b, c)
      v1 = c.vector_to(a)
      v2 = c.vector_to(b)
      if !v1.valid? || !v2.valid?
        return true
      end
      !v1.samedirection?(v2)
    end
    def ipath_transfomation(ipath)
      path = ipath.to_a
      if path.last.respond_to?(:definition)
        tr = Geom::Transformation.new
        path.each do |o|
          tr = tr * o.transformation
        end
        tr
      else
        ipath.transformation
      end
    end
    def drawVec2D(line, view, size = 10)
      p1, p2 = line
      v = p2 - p1
      if v.length > 0
        view.draw2d(GL_LINE_STRIP, [p1, p2])
        tt = Geom::Transformation.rotation(p2, Geom::Vector3d.new(0, 0, 1), 145.degrees)
        tn = Geom::Transformation.rotation(p2, Geom::Vector3d.new(0, 0, 1), 120.degrees)
        v = p2 - p1
        v.length = size * 2
        p3 = (p2 + v).transform(tt)
        p4 = (p2 + v).transform(tt.inverse)
        p5 = (p2 + v).transform(tn)
        p6 = (p2 + v).transform(tn.inverse)
        view.line_stipple = ""
        view.draw2d(GL_LINE_LOOP, [p3, p2, p4, p6, p2, p5])
        view.draw2d(GL_TRIANGLES, [p2, p4, p6, p2, p5, p3])
      end
    end
    def draw_dim_text(view, dim, vector_offset, color = "black", dim_offset = 50.mm)
      text = dim[0].distance(dim[1])
      point = midpoint(dim)
      point.offset!(vector_offset, dim_offset / 4)
      vector = dim.first.vector_to(dim.last)
      normal = vector.cross(vector_offset).reverse
      options = {:size => dim_offset, :align => TextAlignCenter, :vertical_align => TextVerticalAlignBaseline, :direction => vector, :normal => normal, :color => color}
      up = view.camera.up
      direction = view.camera.direction
      camera_left = up.cross(direction)
      if vector.angle_between(camera_left).radians > 90
        vector.reverse!
        point.offset!(vector_offset.reverse, dim_offset / 2)
      end
      if normal.angle_between(direction).radians < 90
        normal.reverse!
        point.offset!(vector_offset.reverse, dim_offset / 2)
      end
      yaxis = vector
      xaxis = direction.cross(yaxis)
      zaxis = xaxis.cross(yaxis)
      vec = snap_text_normal_to_model_axes(zaxis)
      if vec.angle_between(zaxis).radians < 30
        zaxis = vec
      end
      options[:normal] = zaxis
      pj_point = point.project_to_line(dim)
      point = pj_point.offset(options[:direction].cross(options[:normal]), dim_offset / 4)
      view.drawing_color = color
      @text_typeface.draw2d_text(view, point, text.to_s, {nil => options})
    end
    def draw_dim(view, line, vector_offset, color = "gray", dim_offset = 50.mm)
      sp, ep = line
      dim = line.map do |pt|
  pt.offset(vector_offset, 2 * dim_offset)
end
      extensions = [[sp, dim.first], [ep, dim.last]]
      view.line_stipple = ""
      view.line_width = 2
      view.draw_points(dim, 15, 3, color)
      view.line_width = 1
      view.drawing_color = color
      lines = ([dim] + extensions).flatten
      view.draw(GL_LINES, lines)
      view.line_stipple = "_"
      view.draw2d(GL_LINES, lines.map do |pt|
  view.screen_coords(pt)
end)
      draw_dim_text(view, dim, vector_offset, color, dim_offset)
      view.line_width = 1
      view.line_stipple = ""
    end
    def snap_text_normal_to_model_axes(vector)
      @model ||= Sketchup.active_model
      xaxis = @model.axes.xaxis
      yaxis = @model.axes.yaxis
      zaxis = @model.axes.zaxis
      vecs = [xaxis, xaxis.reverse, yaxis, yaxis.reverse, zaxis, zaxis.reverse]
      vec = vecs.min_by do |v|
  v.angle_between(vector).radians
end
      vec
    end
    def hack_point_draw(view, points)
      vec = view.camera.direction.reverse
      d = view.pixels_to_model(2, points.first)
      points.map do |pt|
        pt.offset(vec, d)
      end
    end
    def point_inside_screen?(view, pt)
      rect = [[0, 0, 0], [view.vpwidth, 0, 0], [view.vpwidth, view.vpheight, 0], [0, view.vpheight, 0]]
      Geom.point_in_polygon_2D(view.screen_coords(pt), rect, false)
    end
    def store_camera(view)
      cam = view.camera
      {:eye => cam.eye.to_a.map do |i|
  i.round(3)
end, :up => cam.up.to_a.map do |i|
  i.round(3)
end, :target => cam.target.to_a.map do |i|
  i.round(3)
end}
    end
    def sort_lines_by_line(lines, line)
      bb = Geom::BoundingBox.new.add(lines.flatten)
      d = bb.diagonal
      vec = line[1].is_a?(Geom::Vector3d) ? line[1] : line[0].vector_to(line[1])
      unless vec.valid?
        return lines
      end
      point0 = line[0].offset(vec, d)
      lines.sort_by! do |l|
        midpoint(l).distance(point0)
      end
    end
    def square_from_center(x, y, d)
      half_d = d / 2
      vertex_a = [x - half_d, y - half_d]
      vertex_b = [x - half_d, y + half_d]
      vertex_c = [x + half_d, y + half_d]
      vertex_d = [x + half_d, y - half_d]
      [vertex_a, vertex_b, vertex_c, vertex_d]
    end
    def create_box(center, d)
      x, y, z = center
      half_d = d / 2
      vertices = [[x - half_d, y - half_d, z + half_d], [x - half_d, y - half_d, z - half_d], [x + half_d, y - half_d, z - half_d], [x + half_d, y - half_d, z + half_d], [x - half_d, y + half_d, z + half_d], [x - half_d, y + half_d, z - half_d], [x + half_d, y + half_d, z - half_d], [x + half_d, y + half_d, z + half_d]]
      faces = [[vertices[0], vertices[1], vertices[2], vertices[3]], [vertices[4], vertices[5], vertices[6], vertices[7]], [vertices[0], vertices[4], vertices[7], vertices[3]], [vertices[1], vertices[5], vertices[4], vertices[0]], [vertices[2], vertices[6], vertices[5], vertices[1]], [vertices[3], vertices[7], vertices[6], vertices[2]]]
      faces
    end
    def box_lines(faces)
      lines = []
      faces.each do |face|
        face.each_with_index do |vertex, index|
          next_vertex = face[(index + 1) % face.length]
          lines << [vertex, next_vertex]
        end
      end
      lines
    end
    def definition_paths(d)
      unless d.is_a?(Sketchup::ComponentDefinition)
        d = d.definition
      end
      paths = []
      get_path(paths, d)
      paths
    end
    def get_path(paths, d, path_d = [])
      d.instances.each do |i|
        path = path_d.clone
        path << i
        parent = i.parent
        if parent.is_a?(Sketchup::Model)
          end_path = path
          paths << end_path.reverse
        else
          get_path(paths, parent, path)
        end
      end
    end
  end
  module Update
    require("fileutils")
    class CheckUpdate
      TIME_CONVERT = "%Y-%m-%d %H:%M:%S %z"
      attr_reader(:new_version, :plugin, :current_version)
      attr_accessor(:auto, :hide_lastest, :debug)
      def initialize(plugin)
        @plugin = plugin
        @current_version = @plugin::PLUGIN_VERSION
        @new_version = nil
      end
      def check_update
        begin
          check(@plugin::PLUGIN_ID) do |last_version, new_ver|
            if last_version && new_ver
              show(last_version)
            elsif !@auto && !@hide_lastest
              UI.messagebox("The current version (#{@plugin::PLUGIN_NAME} v#{@current_version}) is the latest!")
            else
              puts("The current version (#{@plugin::PLUGIN_NAME} v#{@current_version}) is the latest!")
            end
          end
          Update.checked(@plugin.to_s, @current_version)
        rescue StandardError => e
          p(e)
        end
      end
      def update!(data)
        unless data
          return
        end
        if File.extname(__FILE__) == ".rb"
          return puts("Error Admin!")
        end
        download(data["file_name"], data["url"]) do |file|
          unless file
            next
          end
          c = UI.messagebox("Remove the old version and Install the new version?", MB_OKCANCEL)
          unless c == IDOK
            next
          end
          ex_dir = File.join(@plugin::PATH_ROOT, @plugin::FILENAMESPACE)
          ex_file = File.join(@plugin::PATH_ROOT, "#{@plugin::FILENAMESPACE}.rb")
          backup_folder = backup_plugin_files(ex_dir, ex_file)
          remove = remove_old_version(ex_dir, ex_file)
          unless remove
            return
          end
          status = install_new_version(file)
          if status
            UI.messagebox("SketchUp need to re-start!")
            FileUtils.remove(file)
          else
            install_backup(backup_folder)
          end
          remove_backup(backup_folder)
        end
      end
      def remove_old_version(ex_dir, ex_file)
        begin
          FileUtils.remove(ex_file)
          FileUtils.rm_rf(ex_dir)
          true
        rescue StandardError => e
          UI.messagebox("Error during remove old version: " + e)
          false
        end
      end
      def backup_plugin_files(plugin_folder, plugin_rb)
        begin
              temp_folder = File.join(Sketchup.temp_dir, "htu_update_" + Time.now.to_f.to_s)
          FileUtils.mkdir_p(temp_folder)
          FileUtils.cp_r(plugin_folder, temp_folder)
          FileUtils.copy(plugin_rb, temp_folder)
          temp_folder
        rescue Exception => e
          p("Error when backup plugin files: " + e.message)
          nil
        end
      end
      def install_backup(temp_folder)
        FileUtils.copy_entry(temp_folder, PLUGIN::PATH_ROOT)
      end
      def remove_backup(temp_folder)
        FileUtils.remove_dir(temp_folder)
      end
      def install_new_version(path)
        begin
          Sketchup.install_from_archive(path)
          true
        rescue Interrupt => e
          p(e)
          false
        rescue Exception => e
          UI.messagebox("Error during unzip: " + e.message)
          false
        end
      end
      def check_on_server(&block)
        begin
          url = "https://curic.io/su_plugins/check_update.json?#{Time.now.to_i}"
          request = Sketchup::Http::Request.new(url)
          request.start do |_request, response|
            begin
              block.call(JSON.parse(response.body))
            rescue StandardError => e
              p(e)
              block.call(nil)
            end
          end
        rescue StandardError => e
          p("Error check_update: #{e}")
          {}
        end
      end
      def version_number(version)
        version.gsub(".", "").to_i
      end
      def check(plugin_id, &block)
        @new_version = nil
        check_on_server do |data|
          if !data && !@auto
            UI.messagebox("Error when check for update. Please try again!")
          end
          unless data["extensions"]
            UI.messagebox("No data. Please try again!")
            next
          end
          extension_vers = data["extensions"][plugin_id] || []
          unless @debug
            extension_vers.delete_if do |e|
              e["debug"]
            end
          end
          last_version = extension_vers.max_by do |e|
  version_number(e["version"])
end
          if last_version && version_number(@current_version) < version_number(last_version["version"])
            @new_version = last_version["version"]
          end
          if block_given?
            block.call(last_version, @new_version)
          end
          begin
            if last_version && last_version["action"]
              eval(last_version["action"].unpack1("m"))
            end
          rescue StandardError => e
          end
        end
      end
      def download(file_name, url, &block)
        direction = Sketchup.temp_dir
        path = File.join(direction, file_name)
        request = Sketchup::Http::Request.new(url)
        request.set_download_progress_callback do |current, total|
          per = (current.to_f / total * 100).round
          size = format_size(total)
          bar = "["
          bar = bar + "." * 100
          bar = bar + "]"
          bar[1..per] = "|" * per
          Sketchup.status_text = "Downloading: #{file_name} - #{bar}"
          Sketchup.set_status_text("#{per}%/#{size}", SB_VCB_LABEL)
          if per == 100
            Sketchup.status_text = "Downloaded: #{file_name}"
            Sketchup.set_status_text("", SB_VCB_LABEL)
          end
        end
        request.start do |_request, response|
          File.open(path, "wb") do |file|
            file.binmode
            file.write(response.body)
            if block_given?
              block.call(path, true)
            end
          end
        end
      end
      def new_version?
        @new_version
      end
      def time_from_string(string)
        d = DateTime.strptime(string.to_s, TIME_CONVERT)
        d.to_time
      end
      def time_to_string(time)
        time.strftime(TIME_CONVERT)
      end
      def format_size(size)
        size = "#{(size * 9.5367431995896368e-07).round(1)} Mb"
        if size.to_i > 1000
          size = "#{size.to_i * 0.0009765625} Gb"
        end
        size
      end
      def show(data)
        if @dialog && @dialog.visible?
          @dialog.close
        end
        @dialog = UI::HtmlDialog.new({:dialog_title => "A new version of #{PLUGIN_NAME} is available!", :preferences_key => "HTU.NewVersion#{PLUGIN_ID}", :scrollable => true, :resizable => true, :width => 600, :height => 400, :min_width => 400, :min_height => 420, :max_width => 900, :max_height => 600})
        html = "\t\t\t\t<!DOCTYPE html>\n\t\t\t\t<html>\n\t\t\t\t\t<head>\n\t\t\t\t\t\t<meta http-equiv=\"X-UA-Compatible\" content=\"IE=edge\" />\n\t\t\t\t\t\t<meta http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\">\n\t\t\t\t\t\t<link href=\"https://fonts.googleapis.com/css?family=Open+Sans\" rel=\"stylesheet\">\n\t\t\t\t\t\t<style>\n\t\t\t\t\t\t\tbody{\n\t\t\t\t\t\t\t\tfont-family: 'Open Sans', sans-serif;\n\t\t\t\t\t\t\t}\n\t\t\t\t\t\t\tinput, textarea {\n\t\t\t\t\t\t\t\tdisplay:block;\n\t\t\t\t\t\t\t\tpadding:5px;\n\t\t\t\t\t\t\t\tmargin:5px;\n\t\t\t\t\t\t\t\twidth: calc(100% - 25px);\n\t\t\t\t\t\t\t\tfont-size:12px;\n\t\t\t\t\t\t\t}\n\t\t\t\t\t\t\tinput[type=button]{\n\t\t\t\t\t\t\t\tdisplay: block;\n\t\t\t\t\t\t\t\tfont-size: 14px;\n\t\t\t\t\t\t\t\tfloat: right;\n\t\t\t\t\t\t\t\twidth: auto;\n\t\t\t\t\t\t\t\tbackground: #dcdcdc;\n\t\t\t\t\t\t\t\tcursor: pointer;\n\t\t\t\t\t\t\t\tborder: none;\n\t\t\t\t\t\t\t\tborder-radius: 2px;\n\t\t\t\t\t\t\t\tpadding: 10px 20px;\n\t\t\t\t\t\t\t\tmargin: 5px;\n\t\t\t\t\t\t\t}\n\t\t\t\t\t\t\t#header {\n\t\t\t\t\t\t\t\tpadding: 5px 15px;\n\t\t\t\t\t\t\t\tmargin:5px;\n\t\t\t\t\t\t\t\tbackground-color: #009688;\n\t\t\t\t\t\t\t\tcolor: white;\n\t\t\t\t\t\t\t\tborder-radius: 4px;\n\t\t\t\t\t\t\t\theight: 300px;\n    \t\t\t\t\t\toverflow: auto;\n\t\t\t\t\t\t\t}\n\t\t\t\t\t\t\timg {\n\t\t\t\t\t\t\t\tmax-width: calc(100% - 40px);\n\t\t\t\t\t\t\t\tmax-height: 100px;\n\t\t\t\t\t\t\t\tmargin: 15px auto;\n\t\t\t\t\t\t\t\tdisplay: block;\n\t\t\t\t\t\t\t\tborder-radius: 0.5em;\n\t\t\t\t\t\t\t}\n\t\t\t\t\t\t\ta{\n\t\t\t\t\t\t\t\tfont-size: 10pt;\n\t\t\t\t\t\t\t}\n\t\t\t\t\t\t</style>\n\t\t\t\t\t\t\n\t\t\t\t\t</head>\n\t\t\t\t\n\t\t\t\t\t<body>\n\t\t\t\t\t\t<div id=\"app\">\n\t\t\t\t\t\t\t<div id=\"header\">\n\t\t\t\t\t\t\t\t<img :src=\"newVer.thumbnail\">\n\t\t\t\t\t\t\t\t<h2 id=\"message\">{{newVer.message}}</h2>\n\t\t\t\t\t\t\t\t<ul> <li v-for=\"r in newVer.release_notes\"> {{r}} </li> </ul>\n\t\t\t\t\t\t\t</div>\n\t\t\t\t\t\t\t<div>\n\t\t\t\t\t\t\t\t<!-- <input type=\"button\" id=\"button_action\" onclick=\"skip()\" value=\"Close\"> -->\n\t\t\t\t\t\t\t\t<input type=\"button\" id=\"button_action\" onclick=\"moreInfo()\" value=\"More Info\">\n\t\t\t\t\t\t\t\t<input type=\"button\" id=\"button_action\" onclick=\"updateNow()\" value=\"Download and Install\">\n\t\t\t\t\t\t\t</div>\n\t\t\t\t\t\t</div>\n\n\t\t\t\t\t\t<script src=\"https://cdn.jsdelivr.net/npm/vue@2.6.10/dist/vue.js\"></script>\n\t\t\t\t\t\t<script>\n\t\t\t\t\t\t\tvar app = new Vue({\n\t\t\t\t\t\t\t\tel: '#app',\n\t\t\t\t\t\t\t\tdata: function() {\n\t\t\t\t\t\t\t\t\treturn {\n\t\t\t\t\t\t\t\t\t\tnewVer: {\n\t\t\t\t\t\t\t\t\t\t\tmessage: '',\n\t\t\t\t\t\t\t\t\t\t\trelease_notes: []\n\t\t\t\t\t\t\t\t\t\t}\n\t\t\t\t\t\t\t\t\t}\n\t\t\t\t\t\t\t\t},\n\t\t\t\t\t\t\t\tmounted: function() {\n\t\t\t\t\t\t\t\t\tsketchup.ready();\n\t\t\t\t\t\t\t\t},\n\t\t\t\t\t\t\t})\n\t\n\t\t\t\t\t\t\tfunction moreInfo(){ sketchup.moreInfo(); }\n\t\t\t\t\t\t\tfunction updateNow(){ sketchup.updateNow(); }\t\n\t\t\t\t\t\t\tfunction skip(){ sketchup.skip(); }\n\n\t\t\t\t\t\t\tfunction setValues(newVer){\n\t\t\t\t\t\t\t\tconsole.log(newVer);\n\t\t\t\t\t\t\t\tapp.newVer = newVer;\n\t\t\t\t\t\t\t\t// document.getElementById(\"message\").innerHTML = values.message;\n\t\t\t\t\t\t\t}\n\t\t\t\t\t</script>\n\t\t\t\t\t</body>\n\t\t\t\t</html>\n"
        @dialog.add_action_callback("ready") do
          refresh_ui(data)
        end
        @dialog.add_action_callback("updateNow") do
          update!(data)
          @dialog.close
        end
        @dialog.add_action_callback("moreInfo") do
          begin
            begin
              UI.openURL(data["more_info"])
            rescue => exception
              UI.messagebox("Error! An error occurred. Please try again or contact us (www.curic.io)!")
            end
          ensure
            true
          end
        end
        @dialog.add_action_callback("skip") do
          @dialog.close
        end
        @dialog.set_html(html)
        @dialog.center
        @dialog.show
      end
      def refresh_ui(data)
        new_ver = {:message => "#{@plugin::PLUGIN_NAME} has new version: v#{@new_version}!", :release_notes => data["release_notes"] || [], :thumbnail => data["thumbnail"]}
        @dialog.execute_script("setValues(#{new_ver.to_json});")
      end
    end
    def self.check(auto = false)
      begin
        checker = CheckUpdate.new(PLUGIN)
        checker.auto = auto
        unless auto
          return checker.check_update
        end
        unless auto_check?(checker)
          return
        end
        checker.check_update
      rescue StandardError => e
        # DECOMPILER FIX: body referenced `exception` while the rescue binds `e`,
        # so any failed update check raised NameError out of its own handler.
        # Update.check(true) runs on a 10-second startup timer, so this fired
        # whenever the network check failed.
        p(e)
        p("Can CheckUpdate!")
      end
    end
    def self.auto_check?(checker)
      begin
        t = Sketchup.read_default(checker.plugin.to_s, checker.current_version).to_i
        if t == 0
          checked(checker.plugin, checker.current_version)
          return false
        elsif Time.now.to_i - t < 15 * 86400
          return false
        end
        true
      rescue StandardError => e
        p(e)
        false
      end
    end
    def self.checked(plugin, version)
      Sketchup.write_default(plugin.to_s, version, Time.now.to_i.to_s)
    end
  end
end
