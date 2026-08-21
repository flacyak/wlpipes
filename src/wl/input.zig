//! Watches the seat so any interaction dismisses the screensaver.
//!
//! The overlay holds an exclusive keyboard grab, so this is the only thing
//! standing between the user and a session they cannot type into. It errs
//! towards dismissing: every input path sets the same flag.

const std = @import("std");
const posix = std.posix;
const wayland = @import("wayland");
const wl = wayland.client.wl;

/// Pointer motion is ignored for this long after the overlay maps, so a cursor
/// that happens to be moving as it appears does not close it instantly. Keys,
/// buttons and touches are honoured immediately.
///
/// The frame loop owns the clock and raises `accept_motion`; the listeners run
/// inside libwayland callbacks and have no Io to read a timestamp from.
pub const settle_seconds: f32 = 0.3;

pub const Input = struct {
    keyboard: ?*wl.Keyboard = null,
    pointer: ?*wl.Pointer = null,
    touch: ?*wl.Touch = null,

    /// Raised by any input. The frame loop polls it and stops.
    dismissed: bool = false,
    /// Raised by the frame loop once `settle_seconds` have passed.
    accept_motion: bool = false,

    pub fn deinit(self: *Input) void {
        if (self.keyboard) |k| k.release();
        if (self.pointer) |p| p.release();
        if (self.touch) |t| t.release();
        self.* = .{};
    }

    fn dismiss(self: *Input) void {
        self.dismissed = true;
    }

    /// Motion only counts once the settle window has passed.
    fn dismissOnMotion(self: *Input) void {
        if (self.accept_motion) self.dismiss();
    }
};

/// Starts listening. `input` must outlive the connection: the listeners hold a
/// pointer to it.
pub fn watch(input: *Input, seat: *wl.Seat) void {
    input.* = .{};
    seat.setListener(*Input, onSeatEvent, input);
}

/// The seat announces which devices exist, and may revise that at any time —
/// unplugging a keyboard mid-session is normal.
fn onSeatEvent(seat: *wl.Seat, event: wl.Seat.Event, input: *Input) void {
    switch (event) {
        .capabilities => |caps| syncDevices(seat, caps.capabilities, input),
        .name => {},
    }
}

fn syncDevices(seat: *wl.Seat, caps: wl.Seat.Capability, input: *Input) void {
    if (caps.keyboard and input.keyboard == null) {
        input.keyboard = seat.getKeyboard() catch null;
        if (input.keyboard) |k| k.setListener(*Input, onKeyboardEvent, input);
    }
    if (caps.pointer and input.pointer == null) {
        input.pointer = seat.getPointer() catch null;
        if (input.pointer) |p| p.setListener(*Input, onPointerEvent, input);
    }
    if (caps.touch and input.touch == null) {
        input.touch = seat.getTouch() catch null;
        if (input.touch) |t| t.setListener(*Input, onTouchEvent, input);
    }
}

fn onKeyboardEvent(_: *wl.Keyboard, event: wl.Keyboard.Event, input: *Input) void {
    switch (event) {
        // The compositor hands us a file descriptor for the keymap whether we
        // want it or not. We do not interpret keysyms — any key dismisses — so
        // close it rather than leaking one per keymap change.
        // Closed via the raw syscall: this runs inside a libwayland
        // callback, which has no Io to hand std.Io.File.close.
        .keymap => |keymap| _ = posix.system.close(keymap.fd),
        .key => |key| {
            if (key.state == .pressed) input.dismiss();
        },
        // Modifiers alone do not dismiss: a stray Shift should not count, and
        // the press that follows will.
        .modifiers, .enter, .leave, .repeat_info => {},
    }
}

fn onPointerEvent(_: *wl.Pointer, event: wl.Pointer.Event, input: *Input) void {
    switch (event) {
        .motion => input.dismissOnMotion(),
        .button, .axis => input.dismiss(),
        else => {},
    }
}

fn onTouchEvent(_: *wl.Touch, event: wl.Touch.Event, input: *Input) void {
    switch (event) {
        .down, .motion => input.dismiss(),
        else => {},
    }
}

const testing = std.testing;

test "a fresh input is not dismissed" {
    const input: Input = .{};
    try testing.expect(!input.dismissed);
}

test "any direct input dismisses" {
    var input: Input = .{};
    input.dismiss();
    try testing.expect(input.dismissed);
}

test "motion is ignored during the settle window" {
    var input: Input = .{};
    input.dismissOnMotion();
    try testing.expect(!input.dismissed);
}

test "motion dismisses once the settle window has passed" {
    var input: Input = .{ .accept_motion = true };
    input.dismissOnMotion();
    try testing.expect(input.dismissed);
}

test "a key press dismisses even inside the settle window" {
    // The settle window exists only for a drifting cursor. A deliberate
    // keystroke must never be swallowed, or the overlay looks unresponsive
    // and the user is stuck staring at a screensaver eating their keyboard.
    var input: Input = .{ .accept_motion = false };
    input.dismiss();
    try testing.expect(input.dismissed);
}

test "deinit clears the dismissal state" {
    var input: Input = .{ .dismissed = true, .accept_motion = true };
    input.deinit();
    try testing.expect(!input.dismissed);
    try testing.expect(!input.accept_motion);
}
