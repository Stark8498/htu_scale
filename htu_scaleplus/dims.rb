module TRINH_VAN_PHUC::HTU_ScalePlus
  module DimsUI
    def self.refresh_workspace
      @model = Sketchup.active_model
      @view = @model.active_view
      @selection = @model.selection
      @materials = @model.materials
      @pages = @model.pages
      @path = File.join(File.dirname(__FILE__), "ui")
    end
    class << self
      attr_reader(:dialog)
      attr_accessor(:disable_ui)
    end
    @disable_ui = false
    def self.show_dialog
      refresh_workspace
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
      else
        toggle_dialog
      end
    end
    def self.toggle_active(_active)
      unless @dialog && @dialog.visible?
        return
      end
      refresh_dialog
    end
    def self.close_dialog
      if @dialog && @dialog.visible?
        toggle_dialog
      end
    end
    def self.toggle_dialog
      if @dialog && @dialog.visible?
        return @dialog.close
      end
      refresh_workspace
      @dialog = UI::HtmlDialog.new({:dialog_title => PLUGIN_NAME.to_s, :preferences_key => "#{PLUGIN_NAME}.dialog.dims", :scrollable => true, :resizable => true, :width => 650, :min_width => 380, :max_width => 1000, :height => 500, :min_height => 500, :max_height => 1000, :left => 500, :top => 200})
      html = File.join(@path, "html/dims.html")
      @dialog.set_file(html)
      add_action_callback
      @dialog.show
    end
    def self.add_action_callback
      @dialog.add_action_callback("ready") do |_action, _width, _height|
        refresh_dialog
      end
      @dialog.add_action_callback("saveDims") do |_action, table|
        save_dims(table)
      end
      @dialog.add_action_callback("exportDims") do |_action, table|
        export(table)
      end
      @dialog.add_action_callback("loadDims") do |_action, method|
        load_table(method)
      end
      @dialog.add_action_callback("setDim") do |_action, dim|
        model = Sketchup.active_model
        model.start_operation("Remove Dims", true)
        set_dim(dim)
        model.commit_operation
        Sketchup.active_model.select_tool(nil)
        Sketchup.focus
        id = UI.start_timer(0.049999999988358468) do
  UI.stop_timer(id)
  Sketchup.send_action("selectScaleTool:")
end
      end
      @dialog.add_action_callback("removeAll") do
        model = Sketchup.active_model
        model.start_operation("Remove Dims", true)
        remove_dims
        model.commit_operation
      end
      @dialog.add_action_callback("refresh_dialog") do
        refresh_dialog
      end
    end
    def self.save_dims(table)
      if table.empty?
        return UI.messagebox("No dimensions!")
      end
      objects = selected_objects
      if objects.empty?
        return UI.beep
      end
      model = Sketchup.active_model
      model.start_operation("Convert layer", true)
      dims = {}
      table.each do |row|
        dim = row["dim"].to_l
        len = row["len"]
        dims[len] ||= []
        unless dims[len].include?(dim)
          dims[len] << dim
        end
      end
      objects.each do |object|
        ["lenx", "leny", "lenz"].each do |l|
          PLUGIN.clear_object_dims(object, l)
        end
        dims.each do |len, ds|
          ds.each do |d|
            if d == 0
              next
            end
            PLUGIN.save_dim_to_object(len, d, object)
          end
        end
      end
      model.commit_operation
      refresh_dialog
    end
    def self.set_dim(dim)
      object = selected_object
      unless object
        return UI.beep
      end
      PLUGIN.active_overlay.dim_scale.set_dim(dim["len"], dim["dim"].to_l)
    end
    def self.remove_dims
      object = selected_object
      unless object
        return
      end
      ["lenx", "leny", "lenz"].each do |l|
        PLUGIN.clear_object_dims(object, l)
      end
    end
    def self.load_from_csv(path)
      unless File.exist?(path)
        return
      end
      data = []
      raw = File.readlines(path)
      raw[1..-1].each do |line|
        rows = line.split(",").map(&:chomp)
        len = rows[0]
        dim = rows[1].to_l
        d = {:len => len, :dim => dim}
        data << d
      end
      data
    end
    def self.save_table(table, path = nil)
      path ||= TEMP_DIMS
      # A p() of the whole table went here on every save, straight into the user's
      # Ruby Console. Debugging left in.
      unless path
        return
      end
      csv = []
      csv << "len,dim"
      table.each do |row|
        csv << [row["len"], row["dim"]].join(",")
      end
      file = File.new(path, "w")
      file.print(csv.join("\n"))
      file.close
      path
    end
    def self.export(table)
      path = UI.savepanel
      unless path
        return
      end
      unless path[-4..-1] && path[-4..-1].downcase == ".csv"
        path = path + ".csv"
      end
      save_table(table, path)
      UI.messagebox("Export to: #{path}")
    end
    def self.load_table(_method)
      path = UI.openpanel
      unless path
        return
      end
      unless File.extname(path).downcase == ".csv"
        return UI.messagebox("Please select CSV file format!")
      end
      dims = load_from_csv(path)
      data = {}
      data[:table] = dims
      @dialog.execute_script("updateData(#{data.to_json})")
    end
    def self.selected_object
      s = Sketchup.active_model.selection
      o = s[0]
      unless s.length == 1 && o.respond_to?(:definition)
        return
      end
      o
    end
    def self.selected_objects
      s = Sketchup.active_model.selection.to_a.reject do |o|
  o.respond_to?(:blocked?) && o.blocked?
end
      objects = s.grep(Sketchup::ComponentInstance) + s.grep(Sketchup::Group)
      objects
    end
    def self.object_dims(object)
      overlay = PLUGIN.active_overlay
      unless overlay
        return
      end
      tool = overlay.dim_scale
      ["lenx", "leny", "lenz"].flat_map do |len|
        dims = tool.object_dims(object, len)
        dims.map do |dim|
          {:len => len, :dim => dim}
        end
      end
    end
    def self.selection_changed
      refresh_dialog
    end
    def self.refresh_dialog
      if @disable_ui
        return
      end
      unless @dialog && @dialog.visible?
        return
      end
      begin
        active = PLUGIN.active_overlay.dim_scale.active?
      rescue StandardError
        active = false
      end
      objects = selected_objects
      hash = objects.each_with_object({}) do |o, h|
  h[o] = object_dims(o) || []
end
      dims = hash.values.inject do |acc, elem|
  acc & elem
end
      table = dims
      table ||= []
      data = {}
      data[:table] = table
      @dialog.execute_script("updateData(#{data.to_json})")
      os = selected_objects
      @dialog.execute_script("app.selected_objects = #{os.length};")
      @dialog.execute_script("app.active = #{active};")
    end
    def self.data_from_csv(path)
      data = {}
      raw = File.readlines(path)
      raw[1..-1].each do |line|
        rows = line.split(",")
        user, vbo = rows[0..1].map(&:chomp)
        # A puts of every row was here. Left-over debugging: it printed the whole
        # file into the user's Ruby Console, one line at a time, with no way to
        # turn it off.
        data[user] = vbo
      end
      data
    end
    def self.tags_to_hash
      m = Sketchup.active_model
      layers = m.layers.sort_by(&:name)
      layers.map do |l|
        {:name => l.name, :display_name => l.display_name}
      end
    end
  end
end
