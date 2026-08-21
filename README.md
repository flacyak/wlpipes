# pipes

The Windows 95 *3D Pipes* screensaver, rebuilt as a native Wayland client.

Targets Arch Linux + Hyprland. Draws itself as a fullscreen `wlr-layer-shell`
overlay, dismisses on any input, and is driven by `hypridle`.

## Status

Under construction, landing as a stack of reviewable PRs:

- [x] **1** — build scaffolding, CLI configuration
- [x] **2** — Wayland connection, `xdg-shell` window, EGL context
- [x] **3** — shaders, cylinder and sphere mesh generation
- [x] **4** — instanced rendering, camera
- [x] **5** — the pipe simulation
- [x] **6** — layer-shell overlay, input dismissal, multi-monitor
- [x] **7** — packaging, `hypridle` integration
- [x] **8** — the teapot

## Install

The repository is private, so the `PKGBUILD` builds the checkout it sits in
rather than fetching a release tarball:

```sh
cd packaging
makepkg -si
```

That installs `/usr/bin/pipes`, `pipes(1)`, and an example idle configuration
at `/usr/share/doc/pipes-screensaver/hypridle.conf.example`.

## Build

Requires Zig 0.16. CI builds, tests and runs `makepkg` on every push and pull
request, so the package is verified there rather than by hand.

```sh
zig build          # -> zig-out/bin/pipes
zig build test
zig build run -- --help
```

## Usage

```sh
pipes                     # fullscreen overlay on every monitor
pipes --windowed          # ordinary window, for development
pipes --help
```

The overlay covers every monitor on the `overlay` layer, above panels and bars,
and exits on any key, click, pointer motion or touch. Pointer motion is ignored
for the first 300ms so a drifting cursor does not dismiss it instantly.

Exit codes: `0` normal, `1` runtime failure, `2` bad usage.

### Hooking it up to hypridle

```
listener {
    timeout = 300
    on-timeout = pipes
    on-resume = pkill -x pipes
}
```

`on-resume` is belt and braces: the screensaver already exits on its own input.

### A warning

The overlay takes an **exclusive keyboard grab**. If its input handling breaks,
your session becomes untypeable. When changing anything under `src/wl/`, test
with `--windowed` first, where the compositor keeps the keyboard, and run the
overlay with `--max-seconds N` until you trust it.

## Credit

The pipe-growth algorithm follows xscreensaver's `hacks/glx/pipes.c` by Marcelo
Vianna (1997), including its turn-probability curve and colour palette.
