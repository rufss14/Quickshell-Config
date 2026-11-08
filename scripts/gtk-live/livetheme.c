/* livetheme — makes RUNNING GTK4 / libadwaita apps follow the shell's palette.
 *
 * GTK reads ~/.config/gtk-4.0/gtk.css once, at app start, and never again; libadwaita apps
 * (Nautilus, Mission Center, …) also ignore the gtk-theme key, so no gsettings toggle
 * repaints one that is already open (reload-theme.sh step 7 only reaches GTK3). GTK4 dropped
 * GTK_MODULES. What every GTK4 app still does is scan GIO modules (GIO_EXTRA_MODULES), so
 * this is a GIO module that rides inside each app, watches the stylesheet the shell writes
 * and, when it changes, reloads it into a style provider of its own one step above the
 * user stylesheet.
 *
 * It is loaded into EVERY GLib process that sees GIO_EXTRA_MODULES (shells, portals, the
 * browser…), so it links against GLib/GIO only, finds GTK with dlsym, and does nothing — and
 * is not even kept loaded — in a process that isn't a GTK4 app.
 *
 * What differs from the version it grew out of, and why:
 *   · Watches $XDG_CONFIG_HOME/gtk-4.0/gtk.css — the file reload-theme.sh / apply-wallpaper.sh
 *     already write — not ~/.cache/wal/gtk4.css, which only exists behind a pywal template
 *     this repo deliberately stopped depending on. Symlinks are resolved first (an older
 *     setup points gtk.css into ~/.cache/wal, and inotify does not follow a link).
 *   · Monitors the one file, not a directory: ~/.cache/wal is rewritten ~30 times per theme
 *     run, and every open GTK4 app was woken for each of them.
 *   · Polls for the display with a bounded timeout. The idle source it replaces re-ran on
 *     EVERY main-loop iteration for as long as there was no display — a GTK4 process that
 *     never opens one (a service, a test) pinned a core.
 *   · Reads the file itself and skips an empty one. The shell truncates gtk.css before it
 *     writes it; loading in that gap would hand the app an empty sheet, i.e. libadwaita's
 *     default colours for a frame.
 *
 * Build (not wired into anything yet):
 *   gcc -shared -fPIC -O2 -Wall -o libgiolivetheme.so livetheme.c $(pkg-config --cflags --libs gio-2.0) -ldl
 *
 * Debug: LIVETHEME_DEBUG=1 in an app's environment logs to its stderr.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <gio/gio.h>
#include <glib/gstdio.h>
#include <limits.h>
#include <stdlib.h>

#define USER_PRIORITY   800   /* GTK_STYLE_PROVIDER_PRIORITY_USER; ours goes one above */
#define DEBOUNCE_MS     80    /* an in-place writer touches the file more than once */
#define SETTLED_MS      10    /* the write is DONE (atomic rename / done-hint): don't wait */
#define ATTACH_POLL_MS  100
#define ATTACH_TRIES    100   /* ~10s for the app to open its display, then give up */

#define DEBUG(...) G_STMT_START { if (debug) g_printerr("livetheme: " __VA_ARGS__); } G_STMT_END

static void *(*p_display_default)(void);
static void *(*p_provider_new)(void);
static void (*p_load_string)(void *, const char *);   /* GTK >= 4.12 */
static void (*p_load_path)(void *, const char *);     /* deprecated in 4.12, the fallback */
static void (*p_add_provider)(void *, void *, unsigned);

static void *provider;
static gchar *css_path;
static guint reload_source;
static gboolean started, debug;

static void apply(void) {
  gchar *css = NULL;
  if (!g_file_get_contents(css_path, &css, NULL, NULL) || !*css) { g_free(css); return; }
  if (p_load_string) p_load_string(provider, css);
  else p_load_path(provider, css_path);
  g_free(css);
}

static gboolean reload_cb(gpointer data) {
  gint64 t = g_get_monotonic_time();
  reload_source = 0;
  apply();
  DEBUG("reloaded in %.1f ms\n", (g_get_monotonic_time() - t) / 1000.0);
  return G_SOURCE_REMOVE;
}

/* The shell replaces the file by rename (CREATED / CHANGES_DONE_HINT): complete the moment it
 * lands, so reload at once — this is on the wave's critical path, the app has to have repainted
 * under the curtain before the front arrives. A bare CHANGED is an in-place writer mid-write
 * (pywal's own template output truncates and rewrites): wait for it to go quiet. */
static void changed_cb(GFileMonitor *m, GFile *f, GFile *other, GFileMonitorEvent ev, gpointer d) {
  if (ev == G_FILE_MONITOR_EVENT_DELETED || ev == G_FILE_MONITOR_EVENT_ATTRIBUTE_CHANGED) return;
  gboolean settled = ev == G_FILE_MONITOR_EVENT_CREATED || ev == G_FILE_MONITOR_EVENT_CHANGES_DONE_HINT
                  || ev == G_FILE_MONITOR_EVENT_MOVED_IN || ev == G_FILE_MONITOR_EVENT_RENAMED;
  DEBUG("file event %d\n", ev);
  if (reload_source) g_source_remove(reload_source);
  reload_source = g_timeout_add(settled ? SETTLED_MS : DEBOUNCE_MS, reload_cb, NULL);
}

static gboolean attach_cb(gpointer data) {
  static int tries;
  void *display = p_display_default();
  if (!display) {
    if (++tries < ATTACH_TRIES) return G_SOURCE_CONTINUE;
    DEBUG("no display after %d tries, giving up\n", tries);
    return G_SOURCE_REMOVE;
  }

  provider = p_provider_new();
  apply();
  p_add_provider(display, provider, USER_PRIORITY + 1);

  GFile *file = g_file_new_for_path(css_path);
  GFileMonitor *mon = g_file_monitor_file(file, G_FILE_MONITOR_NONE, NULL, NULL);
  if (mon) g_signal_connect(mon, "changed", G_CALLBACK(changed_cb), NULL);   /* kept for the process's life */
  g_object_unref(file);
  DEBUG("attached to %s%s\n", css_path, mon ? "" : " (no monitor)");
  return G_SOURCE_REMOVE;
}

void g_io_module_load(GIOModule *module) {
  if (started) return;
  debug = g_getenv("LIVETHEME_DEBUG") != NULL;

  unsigned (*major)(void) = dlsym(RTLD_DEFAULT, "gtk_get_major_version");
  p_display_default = dlsym(RTLD_DEFAULT, "gdk_display_get_default");
  p_provider_new    = dlsym(RTLD_DEFAULT, "gtk_css_provider_new");
  p_load_string     = dlsym(RTLD_DEFAULT, "gtk_css_provider_load_from_string");
  p_load_path       = dlsym(RTLD_DEFAULT, "gtk_css_provider_load_from_path");
  p_add_provider    = dlsym(RTLD_DEFAULT, "gtk_style_context_add_provider_for_display");
  if (!major || !p_display_default || !p_provider_new || !p_add_provider
      || !(p_load_string || p_load_path) || major() != 4)
    return;   /* not a GTK4 app: return WITHOUT pinning, so GIO unloads us again */

  started = TRUE;
  g_type_module_use(G_TYPE_MODULE(module));   /* stay resident: our timeouts and monitor live in this .so */

  const gchar *override = g_getenv("LIVETHEME_CSS");
  gchar *want = override && *override ? g_strdup(override)
              : g_build_filename(g_get_user_config_dir(), "gtk-4.0", "gtk.css", NULL);
  char resolved[PATH_MAX];
  css_path = realpath(want, resolved) ? g_strdup(resolved) : g_strdup(want);
  g_free(want);

  g_timeout_add(ATTACH_POLL_MS, attach_cb, NULL);
}

void g_io_module_unload(GIOModule *module) {}
gchar **g_io_module_query(void) { return NULL; }
