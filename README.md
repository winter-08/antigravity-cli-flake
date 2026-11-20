# antigravity-cli-flake

Nix flake for [Google Antigravity CLI (`agy`)](https://github.com/google-antigravity/antigravity-cli) across `x86_64-linux`, `aarch64-linux`, and `aarch64-darwin` (plus `x86_64-darwin` via `overlays.default` on `nixpkgs-26.05-darwin`).

## Why not `nixpkgs`?

1. **Release cadence:** Upstream cuts releases nearly daily; pinning a dedicated flake lets you bump `antigravity-cli` without rolling all of `nixpkgs`.
2. **Hermetic ELF linking on Linux:** `nixpkgs` runs `autoPatchelfHook` without `glibc` in `buildInputs`, setting `PT_INTERP` while leaving `DT_RUNPATH` unset—so on hosts with `envfs` (`/lib -> /usr/lib`), `ld-linux` resolves `libc.so.6` through `/lib` instead of `/nix/store`. This derivation stamps an explicit `${glibc}/lib` `DT_RUNPATH` and asserts it during `installCheckPhase`.
3. **Static `musl` variant:** Exposes `packages.<system>.antigravity-cli-musl` (`useMusl = true`) on Linux using upstream's fully static `musl` binary (zero dynamic section).
4. **Full platform matrix & dual mirrors:** Covers `x86_64-darwin` in addition to `aarch64-darwin`, `x86_64-linux`, and `aarch64-linux`, fetching from Google Cloud Storage with GitHub Releases as a SHA-512-verified fallback mirror.
5. **Hermetic runtime `PATH`:** Wraps `agy` with `makeBinaryWrapper --inherit-argv0` so `ripgrep` (`rg`) and `netcat` (`nc`, used by `agy acp --ide-mcp-port`) are always reachable even in headless environments, with `extraRuntimeInputs` available via `.override`.

## Usage

```nix
{
  inputs.antigravity-cli = {
    url = "github:winter-08/antigravity-cli-flake";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Use `inputs.antigravity-cli.packages.${system}.antigravity-cli` (or `.antigravity-cli-musl` on Linux), or apply `inputs.antigravity-cli.overlays.default`.

To append desktop helpers (such as `xdg-open`, `wl-copy`, or PipeWire's `pw-cat` for `/voice` and `agy mic-serve`) without bloating headless closures:

```nix
pkgs.antigravity-cli.override {
  extraRuntimeInputs = [
    pkgs.pipewire
    pkgs.wl-clipboard
    pkgs.xdg-utils
  ];
}
```

## Updating

A scheduled workflow checks upstream every 6 hours, updates `sources.json` directly from upstream's SHA-512 release manifest, builds and verifies both the `glibc` and static `musl` derivations, and pushes. To run locally:

```sh
nix run .#update
nix build .#antigravity-cli
```
