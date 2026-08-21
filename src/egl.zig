//! EGL display, context and per-surface window binding for the Wayland
//! platform. Knows nothing about which shell protocol produced the surface.

const std = @import("std");

pub const c = @cImport({
    @cInclude("EGL/egl.h");
    @cInclude("EGL/eglext.h");
    @cInclude("wayland-egl.h");
});

pub const Error = error{
    NoDisplay,
    InitFailed,
    NoConfig,
    NoContext,
    NoSurface,
    MakeCurrentFailed,
    SwapFailed,
};

pub const Instance = struct {
    display: c.EGLDisplay,
    config: c.EGLConfig,
    context: c.EGLContext,
    /// Whether multisampling survived config selection.
    multisampled: bool,

    pub fn deinit(self: *Instance) void {
        _ = c.eglMakeCurrent(self.display, null, null, null);
        _ = c.eglDestroyContext(self.display, self.context);
        _ = c.eglTerminate(self.display);
        _ = c.eglReleaseThread();
    }
};

/// Brings up EGL against a `wl_display`. GLES 3.0, 24-bit depth, opaque.
pub fn init(native_display: *anyopaque) Error!Instance {
    const display = try openDisplay(native_display);
    errdefer _ = c.eglTerminate(display);

    if (c.eglBindAPI(c.EGL_OPENGL_ES_API) == c.EGL_FALSE) return Error.InitFailed;

    const choice = try chooseConfig(display);
    const context = try createContext(display, choice.config);

    return .{
        .display = display,
        .config = choice.config,
        .context = context,
        .multisampled = choice.multisampled,
    };
}

fn openDisplay(native_display: *anyopaque) Error!c.EGLDisplay {
    const display = c.eglGetDisplay(@ptrCast(native_display)) orelse
        return Error.NoDisplay;

    var major: c.EGLint = undefined;
    var minor: c.EGLint = undefined;
    if (c.eglInitialize(display, &major, &minor) == c.EGL_FALSE) return Error.InitFailed;
    return display;
}

const ConfigChoice = struct {
    config: c.EGLConfig,
    multisampled: bool,
};

/// Prefers a 4x multisampled config, falling back to a plain one. MSAA is the
/// only antialiasing the pipes get, but it is not worth failing to start over.
fn chooseConfig(display: c.EGLDisplay) Error!ConfigChoice {
    if (matchConfig(display, 4)) |config| {
        return .{ .config = config, .multisampled = true };
    }
    if (matchConfig(display, 0)) |config| {
        return .{ .config = config, .multisampled = false };
    }
    return Error.NoConfig;
}

fn matchConfig(display: c.EGLDisplay, samples: c.EGLint) ?c.EGLConfig {
    const attribs = [_]c.EGLint{
        c.EGL_SURFACE_TYPE,    c.EGL_WINDOW_BIT,
        c.EGL_RENDERABLE_TYPE, c.EGL_OPENGL_ES3_BIT,
        c.EGL_RED_SIZE,        8,
        c.EGL_GREEN_SIZE,      8,
        c.EGL_BLUE_SIZE,       8,
        c.EGL_ALPHA_SIZE,      0,
        c.EGL_DEPTH_SIZE,      24,
        c.EGL_SAMPLE_BUFFERS,  if (samples > 0) @as(c.EGLint, 1) else 0,
        c.EGL_SAMPLES,         samples,
        c.EGL_NONE,
    };

    var config: c.EGLConfig = undefined;
    var count: c.EGLint = 0;
    if (c.eglChooseConfig(display, &attribs, &config, 1, &count) == c.EGL_FALSE) return null;
    return if (count > 0) config else null;
}

fn createContext(display: c.EGLDisplay, config: c.EGLConfig) Error!c.EGLContext {
    const attribs = [_]c.EGLint{
        c.EGL_CONTEXT_MAJOR_VERSION, 3,
        c.EGL_CONTEXT_MINOR_VERSION, 0,
        c.EGL_NONE,
    };
    return c.eglCreateContext(display, config, c.EGL_NO_CONTEXT, &attribs) orelse
        Error.NoContext;
}

/// A drawable bound to one `wl_surface`, sized by that surface's configure.
pub const Surface = struct {
    window: *c.wl_egl_window,
    surface: c.EGLSurface,
    width: u31,
    height: u31,

    pub fn deinit(self: *Surface, instance: Instance) void {
        _ = c.eglDestroySurface(instance.display, self.surface);
        c.wl_egl_window_destroy(self.window);
    }

    pub fn resize(self: *Surface, width: u31, height: u31) void {
        if (self.width == width and self.height == height) return;
        c.wl_egl_window_resize(self.window, width, height, 0, 0);
        self.width = width;
        self.height = height;
    }

    pub fn makeCurrent(self: Surface, instance: Instance) Error!void {
        const ok = c.eglMakeCurrent(
            instance.display,
            self.surface,
            self.surface,
            instance.context,
        );
        if (ok == c.EGL_FALSE) return Error.MakeCurrentFailed;
    }

    pub fn swap(self: Surface, instance: Instance) Error!void {
        if (c.eglSwapBuffers(instance.display, self.surface) == c.EGL_FALSE) {
            return Error.SwapFailed;
        }
    }
};

/// Wraps a `wl_surface` in an EGL drawable at the given size.
pub fn createSurface(
    instance: Instance,
    native_surface: *anyopaque,
    width: u31,
    height: u31,
) Error!Surface {
    const window = c.wl_egl_window_create(@ptrCast(native_surface), width, height) orelse
        return Error.NoSurface;
    errdefer c.wl_egl_window_destroy(window);

    const surface = c.eglCreateWindowSurface(
        instance.display,
        instance.config,
        @intFromPtr(window),
        null,
    ) orelse return Error.NoSurface;

    return .{ .window = window, .surface = surface, .width = width, .height = height };
}
