module TRINH_VAN_PHUC::HTU_ScalePlus
  # The Add window: an entry field, an Add button, and the saved list laid out
  # underneath where all of it is visible at once.
  #
  # This replaces the UI.inputbox loop. An inputbox has no read-only text and no
  # list control, so the saved values could only be shown as a dropdown, and it
  # has to be torn down and reopened for every value entered. An HtmlDialog is
  # modeless: it stays put while values are added and the list refreshes in
  # place, which is the whole point.
  #
  # The HTML is inline rather than a file under ui/, because those assets belong
  # to the Vue-based dimension manager and this window is three controls.
  module DimAddDialog
    class << self
      attr_reader :dialog, :object, :axis
    end

    # One heading, not the name of an axis: the list behind this window is
    # shared by all three, so naming the one that was right-clicked would read
    # as a promise that X keeps its own sizes.
    HEADING = "Saved sizes".freeze

    # Reopening points the existing window at the axis just clicked instead of
    # stacking a second one, so right-clicking another dimension retargets it.
    def self.show(object, axis)
      @object = object
      @axis = axis
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        refresh
        return @dialog
      end
      @dialog = UI::HtmlDialog.new(
        # Not "Add Dimensions": Del reaches the same window, because deleting
        # several values is the thing the context menu cannot do.
        :dialog_title => "Dimensions",
        :preferences_key => "#{PLUGIN_NAME}.dialog.add",
        :scrollable => false,
        :resizable => true,
        :width => 320,
        :height => 420,
        :min_width => 260,
        :min_height => 260
      )
      @dialog.set_html(html)
      add_callbacks(@dialog)
      @dialog.show
      refresh
      @dialog
    end

    def self.close
      if @dialog && @dialog.visible?
        @dialog.close
      end
    end

    def self.add_callbacks(dialog)
      dialog.add_action_callback("ready") { refresh }
      dialog.add_action_callback("add") { |_ctx, text| add(text) }
      dialog.add_action_callback("remove") { |_ctx, text| remove(text) }
      dialog.add_action_callback("removeAll") { remove_all }
      dialog.add_action_callback("closeDialog") { close }
    end

    def self.add(text)
      good, bad = DimFavorites.parse(text)
      unless bad.empty?
        return refresh("Cannot read: #{bad.join(', ')} -- nothing added")
      end
      if good.empty?
        return refresh("")
      end
      DimFavorites.add(@object, @axis, good)
      redraw
      refresh("Added #{good.size}")
    end

    # The list is right there, so the value to drop is a click away rather than
    # a trip back through the context menu.
    def self.remove(text)
      value = DimFavorites.list(@object, @axis).find { |v| v.to_s == text.to_s }
      unless value
        return refresh
      end
      DimFavorites.remove(@object, @axis, value)
      redraw
      refresh("Removed #{text}")
    end

    # Confirmed, because Ctrl+Z cannot bring the list back: it lives in
    # preferences, not in the model, so nothing about it is on the undo stack.
    def self.remove_all
      count = DimFavorites.list(@object, @axis).size
      if count.zero?
        return refresh
      end
      answer = UI.messagebox("Delete all #{count} saved sizes?\n\nThis cannot be undone.", MB_YESNO)
      unless answer == IDYES
        return refresh
      end
      DimFavorites.clear(@object, @axis)
      redraw
      refresh("Deleted all")
    end

    # No start_operation around any of these any more: the list moved out of the
    # model's attributes and into preferences, so there is nothing for an
    # operation to wrap and nothing for undo to restore. Only the viewport still
    # needs telling, since the menu shows the same values.
    def self.redraw
      Sketchup.active_model.active_view.invalidate
    rescue StandardError => e
      p(e)
    end

    def self.refresh(message = nil)
      unless @dialog && @dialog.visible?
        return
      end
      values = DimFavorites.list(@object, @axis)
      data = {
        :heading => HEADING,
        :values => values.map(&:to_s),
        :message => message.to_s,
      }
      @dialog.execute_script("render(#{data.to_json})")
      nil
    end

    def self.html
      <<~HTML
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          :root { color-scheme: light dark; }
          body {
            font: 13px/1.4 "Segoe UI", system-ui, sans-serif;
            margin: 0; padding: 12px;
            display: flex; flex-direction: column; height: 100vh;
            box-sizing: border-box;
          }
          h1 { font-size: 12px; font-weight: 600; margin: 0 0 8px; opacity: .6;
               text-transform: uppercase; letter-spacing: .04em; }
          form { display: flex; gap: 6px; }
          input { flex: 1 1 auto; min-width: 0; padding: 6px 8px; font: inherit;
                  border: 1px solid rgba(128,128,128,.5); border-radius: 4px;
                  background: canvas; color: canvastext; }
          button { padding: 6px 12px; font: inherit; border-radius: 4px;
                   border: 1px solid rgba(128,128,128,.5); background: buttonface;
                   color: buttontext; cursor: pointer; }
          #msg { min-height: 16px; margin: 6px 0; font-size: 12px; opacity: .75; }
          #msg.bad { opacity: 1; color: #c0392b; }
          ul { flex: 1 1 auto; overflow-y: auto; margin: 0; padding: 0;
               list-style: none; border: 1px solid rgba(128,128,128,.35);
               border-radius: 4px; }
          li { display: flex; align-items: center; justify-content: space-between;
               padding: 5px 4px 5px 10px; border-bottom: 1px solid rgba(128,128,128,.2); }
          li:last-child { border-bottom: 0; }
          li b { font-weight: 500; }
          li button { border: 0; background: none; opacity: .45; padding: 2px 6px;
                      font-size: 15px; line-height: 1; }
          li button:hover { opacity: 1; color: #c0392b; }
          #empty { padding: 14px 10px; opacity: .5; }
          footer { padding-top: 10px; display: flex; justify-content: space-between; }
          #all:disabled { opacity: .4; cursor: default; }
        </style>
        </head>
        <body>
          <h1 id="heading"></h1>
          <form id="entry">
            <input id="value" placeholder="450  or  45, 200, 400" autocomplete="off">
            <button type="submit">Add</button>
          </form>
          <div id="msg"></div>
          <ul id="list"></ul>
          <footer>
            <button type="button" id="all">Delete all</button>
            <button type="button" id="close">Close</button>
          </footer>

        <script>
        function render(data) {
          document.getElementById('heading').textContent = data.heading;
          var msg = document.getElementById('msg');
          msg.textContent = data.message || '';
          msg.className = /Cannot|gone/.test(data.message || '') ? 'bad' : '';

          document.getElementById('all').disabled = !data.values.length;

          var list = document.getElementById('list');
          list.innerHTML = '';
          if (!data.values.length) {
            var none = document.createElement('div');
            none.id = 'empty';
            none.textContent = 'Nothing saved yet.';
            list.appendChild(none);
            return;
          }
          data.values.forEach(function (v) {
            var li = document.createElement('li');
            var name = document.createElement('b');
            name.textContent = v;
            var del = document.createElement('button');
            del.type = 'button';
            del.textContent = '\\u00d7';
            del.title = 'Remove';
            del.onclick = function () { sketchup.remove(v); };
            li.appendChild(name);
            li.appendChild(del);
            list.appendChild(li);
          });
        }

        document.getElementById('entry').onsubmit = function (e) {
          e.preventDefault();
          var input = document.getElementById('value');
          if (!input.value.trim()) { return; }
          sketchup.add(input.value);
          input.value = '';
          input.focus();
        };
        document.getElementById('all').onclick = function () { sketchup.removeAll(); };
        document.getElementById('close').onclick = function () { sketchup.closeDialog(); };
        window.addEventListener('load', function () {
          sketchup.ready();
          document.getElementById('value').focus();
        });
        </script>
        </body>
        </html>
      HTML
    end
  end
end
