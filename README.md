# svelte-bun2nix-demo

A minimal [SvelteKit](https://svelte.dev/docs/kit) app that is served by [Bun](https://bun.sh)
and packaged for [Nix](https://nixos.org) with [bun2nix](https://github.com/nix-community/bun2nix).
`nix build` produces a **single, self-contained Bun binary** — no `node_modules`, no dev
dependencies in the runtime closure.

## Develop

```sh
bun install
bun run dev        # http://localhost:5173
```

`bun.nix` is regenerated automatically on every install via the `postinstall` script
(`bun2nix -o bun.nix`), so it always tracks `bun.lock`.

## Build with Nix

```sh
nix build            # -> ./result/bin/svelte-bun2nix-demo
nix run              # start the server (defaults to 0.0.0.0:3000)
PORT=8080 nix run    # override host/port via env
```

The binary is produced in two steps inside the derivation:

1. `bun run build` — `svelte-adapter-bun` emits a Bun server under `build/` plus the static
   client assets.
2. `bun build --compile --minify --sourcemap` — AOT-compiles that server into one executable.

The compiled binary's static assets live at `$out/share/svelte-bun2nix-demo/`. Because a
compiled Bun binary sees `import.meta.dir` as a virtual path, the derivation bakes the absolute
store path of the assets into the server handler at build time.

### Why the build stays clean

* `fetchBunDeps` builds an offline Bun cache purely from `bun.nix` — the build never touches
  the network.
* `bun build --compile` bundles only what the server imports at runtime. Vite, Svelte, the
  adapter and TypeScript are build-time only and never enter the binary's closure.

## Install elsewhere

### Flake package / overlay

```nix
{
  inputs.svelte-bun2nix-demo.url = "github:webmasterkai/svelte-bun2nix-demo";

  # then, per system:
  environment.systemPackages = [ inputs.svelte-bun2nix-demo.packages.${system}.default ];
  # or via the overlay: nixpkgs.overlays = [ inputs.svelte-bun2nix-demo.overlays.default ];
}
```

### NixOS module

```nix
{
  imports = [ inputs.svelte-bun2nix-demo.nixosModules.default ];

  services.svelte-bun2nix-demo = {
    enable = true;
    port = 3000;
    openFirewall = true;
  };
}
```

This runs the binary as a hardened `DynamicUser` systemd service.
