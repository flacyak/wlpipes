# pipes

The Windows 95 *3D Pipes* screensaver, rebuilt as a native Wayland client.

Targets Arch Linux + Hyprland. Draws itself as a fullscreen `wlr-layer-shell`
overlay, dismisses on any input, and is driven by `hypridle`.

## Status

Under construction, landing as a stack of reviewable PRs:

- [x] **1** — build scaffolding, CLI configuration
- [ ] **2** — Wayland connection, `xdg-shell` window, EGL context
- [ ] **3** — shaders, cylinder and sphere mesh generation
- [ ] **4** — instanced rendering, camera
- [ ] **5** — the pipe simulation
- [ ] **6** — layer-shell overlay, input dismissal, multi-monitor
- [ ] **7** — packaging, `hypridle` integration
- [ ] **8** — the teapot

## Build

Requires Zig 0.16.

```sh
zig build          # -> zig-out/bin/pipes
zig build test
zig build run -- --help
```

## Usage

```sh
pipes --windowed          # ordinary window, for development
pipes                     # fullscreen overlay
pipes --help
```

While developing the overlay backend, prefer `--windowed`. The overlay takes an
exclusive keyboard grab, so a bug in its input handling can lock you out of your
session; `--max-seconds N` exists as the escape hatch.

## Credit

The pipe-growth algorithm follows xscreensaver's `hacks/glx/pipes.c` by Marcelo
Vianna (1997), including its turn-probability curve and colour palette.
