//! Raw GLES 3.0 entry points. Kept in one place so nothing else needs a
//! `@cImport`, and so a future loader can be swapped in behind this name.

pub const c = @import("gles_c");

/// GL_VENDOR / GL_RENDERER / GL_VERSION, for logging which GPU we landed on.
pub fn getString(name: c.GLenum) []const u8 {
    const raw = c.glGetString(name) orelse return "unknown";
    return @import("std").mem.span(@as([*:0]const u8, @ptrCast(raw)));
}
