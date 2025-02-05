/*
 * Copyright (c) 2018 Matt Harris
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public
 * License along with this program; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301 USA
 *
 * Authored by: Matt Harris <matth281@outlook.com>
 *              Allie Law <allie@cloverleaf.app>
 */

public class MainWindow : Gtk.Window {
    Gtk.Stack stack;
    Gtk.SearchBar search_bar;
    private bool online;
    private View dev;
    public MainWindow (Gtk.Application application) {
        Object (application: application,
        icon_name: "com.github.watsonprojects.easydocs",
        title: "EasyDocs");
    }

    construct {
        set_position (Gtk.WindowPosition.CENTER);

        var header = new Gtk.HeaderBar ();
        header.set_show_close_button (true);

        var header_context = header.get_style_context ();
        header_context.add_class ("default-decoration");

        set_titlebar (header);

        stack = new Gtk.Stack ();
        stack.set_transition_type (Gtk.StackTransitionType.SLIDE_LEFT_RIGHT);

        var window_width = EasyDocs.settings.get_int ("width");
        var window_height = EasyDocs.settings.get_int ("height");
        set_default_size (window_width, window_height);
        var x = EasyDocs.settings.get_int ("window-x");
        var y = EasyDocs.settings.get_int ("window-y");

        if (x != -1 || y != -1) {
            move (x, y);
        }

        this.destroy.connect (() => {
            EasyDocs.settings.set_string ("tab", stack.get_visible_child_name ());
        });

        var stack_switcher = new Gtk.StackSwitcher ();
        stack_switcher.set_stack (stack);
        header.set_custom_title (stack_switcher);

        var vala = new View ();

        online = check_online ();
        if (online) {
            vala.load_uri (EasyDocs.settings.get_string ("last-vala"));
            stack.add_titled (vala, "vala", "Valadoc");
        } else {
            var manager = new Dh.BookManager ();
            manager.populate ();

            var sidebar = new Dh.Sidebar (manager);
            sidebar.link_selected.connect ((source, link) => {
                vala.load_uri (link.get_uri ());
            });

            var pane = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            pane.pack1 (sidebar, false, false);
            pane.add2 (vala);
            pane.set_position (300);

            stack.add_titled (pane, "vala", "Valadoc");
        }

        dev = new View ();
        dev.set_cookies ();
        dev.appcache_init (online);
        dev.load_uri (EasyDocs.settings.get_string ("last-dev"));

        stack.add_titled (dev, "dev", "DevDocs");

        var back = new Gtk.Button.from_icon_name ("go-previous-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
        back.clicked.connect (() => {
            if (stack.get_visible_child_name () == "vala") {
                vala.go_back ();
            } else if (stack.get_visible_child_name () == "dev") {
                dev.go_back ();
            }
        });

        var forward = new Gtk.Button.from_icon_name ("go-next-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
        forward.clicked.connect (() => {
            if (stack.get_visible_child_name () == "vala") {
                vala.go_forward ();
            } else if (stack.get_visible_child_name () == "dev") {
                dev.go_forward ();
            }
        });

        var offline_popover = new PackageList ();

        var offline_button = new Gtk.MenuButton ();
        offline_button.image = new Gtk.Image.from_icon_name ("folder-download-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
        offline_button.popover = offline_popover;
        offline_button.sensitive = online;
        offline_button.valign = Gtk.Align.CENTER;
        offline_button.set_tooltip_text (_("Download offline documentation"));

        header.add (back);
        header.add (forward);
        header.pack_end (offline_button);

        search_bar = create_search_bar ();

        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        vbox.pack_start (stack, true, true, 0);
        vbox.pack_start (search_bar, false, true, 0);

        add (vbox);

        string style = "@define-color colorPrimary #403757;";
        var provider = new Gtk.CssProvider ();

        try {
            provider.load_from_data (style, -1);
        } catch {
            warning ("Couldn't load CSS");
        }

        stack.notify["visible-child"].connect (() => {
            stack_change (provider, offline_button);
        });

        show_all ();

        set_tab ();

        this.delete_event.connect (() => {
            int current_x, current_y, width, height;
            get_position (out current_x, out current_y);
            get_size (out width, out height);

            EasyDocs.settings.set_int ("window-x", current_x);
            EasyDocs.settings.set_int ("window-y", current_y);
            EasyDocs.settings.set_int ("width", width);
            EasyDocs.settings.set_int ("height", height);

            if (dev.uri.contains ("devdocs.io")) {
                EasyDocs.settings.set_string ("last-dev", dev.uri);
            }

            if (online && vala.uri.contains ("valadoc.org")) {
                EasyDocs.settings.set_string ("last-vala", vala.uri);
            }

            return false;
        });
    }

    public void change_tab () {
        var current = stack.get_visible_child_name ();
        if (current == "vala") {
            stack.set_visible_child_name ("dev");
        } else {
            stack.set_visible_child_name ("vala");
        }
    }

    public void toggle_search () {
        var disabled = !search_bar.search_mode_enabled;
        search_bar.search_mode_enabled = disabled;
        if (disabled) {
            var view = get_current_view ();
            view.search_finish ();
        }
    }

    private View? get_current_view () {
        var v = stack.get_visible_child ();
        return (v is View)
                ? v as View
                : null;
    }

    private Gtk.SearchBar create_search_bar () {
        var search_entry = new Gtk.SearchEntry ();
        search_entry.placeholder_text = _("Find in page…");
        search_entry.set_width_chars (60);

        search_entry.search_changed.connect (() => {
            var v = get_current_view ();
            if (v != null) {
                v.search (search_entry.text);
            }
        });

        search_entry.activate.connect (() => {
            var v = get_current_view ();
            if (v != null ) {
                v.search_next ();
            }
        });
        search_entry.show ();

        var next_search = new Gtk.Button.from_icon_name ("go-down-symbolic", Gtk.IconSize.MENU);
        next_search.clicked.connect (() => {
            var v = get_current_view ();
            if (v != null ) {
                v.search_next ();
            }
        });

        next_search.show ();

        var previous_search = new Gtk.Button.from_icon_name ("go-up-symbolic", Gtk.IconSize.MENU);
        previous_search.clicked.connect (() => {
            var v = get_current_view ();
            if (v != null ) {
                v.search_previous ();
            }
        });
        previous_search.show ();

        var hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 5);
        hbox.pack_start (search_entry, false, false, 0);
        hbox.pack_start (previous_search, false, false, 0);
        hbox.pack_start (next_search, false, false, 0);
        hbox.show ();

        var search_bar = new Gtk.SearchBar ();
        search_bar.connect_entry (search_entry);
        search_bar.add (hbox);

        return search_bar;
    }

    private bool check_online () {
        var host = "valadoc.org";
        try {
            var resolve = Resolver.get_default ();
            resolve.lookup_by_name (host, null);
            return true;
        } catch {
            return false;
        }
    }

    private void stack_change (Gtk.CssProvider provider, Gtk.Button offline_button) {
        if (stack.get_visible_child_name () == "vala") {
            Gtk.StyleContext.add_provider_for_screen (Gdk.Screen.get_default (), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

            offline_button.set_visible (true);
        } else {
            Gtk.StyleContext.remove_provider_for_screen (Gdk.Screen.get_default (), provider);

            offline_button.set_visible (false);
        }
    }


    private void set_tab () {
        var tab = EasyDocs.settings.get_string ("tab");
        stack.set_visible_child_name (tab);
    }
}
