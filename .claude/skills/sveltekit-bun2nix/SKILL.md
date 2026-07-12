---
name: sveltekit-bun2nix
description: Package a Bun-based SvelteKit project into a Nix flake with bun2nix, producing a single standalone Bun binary whose runtime closure contains no dev dependencies. Use when a user wants to build/deploy a SvelteKit (or similar Bun-served) app with Nix, "compile SvelteKit to a bun binary", write a flake/default.nix/bun.nix for a Bun web app, or set up a NixOS module/service for a SvelteKit app. Covers svelte-adapter-bun, bun2nix.mkDerivation + fetchBunDeps, the import.meta.dir asset-path gotcha, the fixupPhase/strip gotcha (bare-bun binary exiting 0), an HTTP install check, and a clean flake with package/overlay/app/nixosModule.
---

# SvelteKit → bun2nix package

Turn a Bun-managed SvelteKit project into a reproducible Nix flake that builds **one
self-contained Bun binary**. The binary AOT-compiles the whole server; its runtime closure
holds only the binary + ICU — no `node_modules`, no Vite/Svelte/TypeScript.

## Mental model

A SvelteKit build is **two steps** — and both fit `bun2nix.mkDerivation`, because its default
build phase runs `runHook preBuild` before `bun build $bunBuildFlags`:

1. `preBuild`: `bun run build` → `svelte-adapter-bun` emits a Bun server under `build/`
   (`index.js`, `handler.js`, `server/`) plus static client assets under `build/client/` (and
   `build/prerendered/` if any pages prerender).
2. `bunBuildFlags`: `bun build --compile` AOT-compiles `build/index.js` into a single executable.

Do **not** drop to `bun2nix.hook` + a custom `buildPhase` for this: a custom `buildPhase` flips
mkDerivation's `dontFixup` default back to false, and stdenv's fixupPhase (strip/patchelf)
discards the module graph `bun build --compile` appends to the executable — leaving a bare `bun`
CLI that prints help and **exits 0** (see gotcha below). With mkDerivation and no `buildPhase`
override, `dontFixup = true` holds by construction.

Dev tooling is build-time only and never enters the compiled binary — this is what satisfies
"no dev packages in the output". (The *build* still needs devDeps; that's unavoidable and fine —
`fetchBunDeps` fetches everything in `bun.nix` offline.)

## Gotcha 1: fixupPhase strips the embedded app

`bun build --compile` appends the app's module graph to a copy of the `bun` executable. stdenv's
default fixupPhase (strip/patchelf) discards that appended data. The broken binary doesn't
crash — it degrades into a bare `bun` CLI: prints the help text, **exits 0**, so a systemd
service "starts" successfully and silently deactivates.

`bun2nix.mkDerivation` defaults `dontFixup = true` for exactly this reason — but only when you
don't pass a `buildPhase`. If you must override `buildPhase` (avoid it; use `preBuild` +
`bunBuildFlags`), set `dontFixup = true;` explicitly. Either way, add the HTTP install check
below: exit-code checks cannot catch this failure mode.

## Gotcha 2: `import.meta.dir`

`svelte-adapter-bun`'s `handler.js` locates static assets via `${import.meta.dir}/client` and
`${import.meta.dir}/prerendered`. In a `bun build --compile` binary, `import.meta.dir` resolves
to the **virtual `$bunfs` root**, not the real filesystem — so every static asset and every
`/_app/immutable/*` chunk returns **404** while SSR still works (making it easy to miss).

Fix: in the build phase, before compiling, rewrite `import.meta.dir` to the **absolute Nix store
path** where the assets will be installed, then install `build/client` (+ `prerendered`) there.
Because the store path is known at build time via `${placeholder "out"}`, this is fully
deterministic.

## Recipe

### 1. Project setup (in the repo)

```sh
bun add -d svelte-adapter-bun bun2nix @types/bun
```

- `vite.config.ts` (or `svelte.config.js` on older scaffolds): swap the adapter to
  `import adapter from 'svelte-adapter-bun';`. Newer `sv create` puts the adapter config inside
  `vite.config.ts` under the `sveltekit({ ... })` plugin — no `svelte.config.js` at all.
- `package.json`: add `"postinstall": "bun2nix -o bun.nix"` so `bun.nix` tracks `bun.lock` on
  every install.
- `bunfig.toml`: `[install]\nlinker = "isolated"` (bun2nix default; hoisted is the Darwin
  fallback below).
- Generate the lock-derived Nix expr: `bunx bun2nix -o bun.nix`.
- `.gitignore`: add `result`, `result-*`, `.direnv`. Keep `bun.nix` **tracked**; `build/` stays
  ignored.

> Flakes only see git-tracked files. `git add -A` before `nix build`, or new files are invisible
> to the build.

### 2. `default.nix`

Use `bun2nix.mkDerivation`: no `buildPhase` override (keeps `dontFixup = true`), the vite build
in `preBuild`, the compile via `bunBuildFlags`, and the assets in `postInstall` (the default
install phase installs the binary, then runs `postInstall` from the project root).

```nix
{ lib, stdenv, bun2nix, curl }:
bun2nix.mkDerivation (finalAttrs: {
  pname = "svelte-bun2nix-demo";
  version = "0.0.1";
  src = ./.;

  bunDeps = bun2nix.fetchBunDeps { bunNix = ./bun.nix; };

  # Isolated linker can trip up Vite/SvelteKit on Darwin (per bun2nix hook docs).
  bunInstallFlags = lib.optionals stdenv.hostPlatform.isDarwin [
    "--linker=hoisted"
    "--backend=copyfile"
  ];

  preBuild = ''
    bun run build   # -> build/ (Bun server + static client assets)

    # Bake the absolute store assets path in before compiling (import.meta.dir fix).
    substituteInPlace build/handler.js \
      --replace-fail "import.meta.dir" \
        "\"${placeholder "out"}/share/${finalAttrs.pname}\""
  '';

  # Compile the emitted server, not the app source. Passing bunBuildFlags
  # explicitly also skips mkDerivation's default --bytecode.
  bunBuildFlags = [
    "build/index.js"
    "--outfile"
    finalAttrs.pname
    "--compile"
    "--minify"
    "--sourcemap"
  ];

  postInstall = ''
    mkdir -p $out/share/${finalAttrs.pname}
    cp -r build/client $out/share/${finalAttrs.pname}/client
    [ -d build/prerendered ] && cp -r build/prerendered $out/share/${finalAttrs.pname}/prerendered || true
  '';

  # A fixup-stripped binary exits 0 with bun's help text, so require real HTTP.
  doInstallCheck = true;
  nativeInstallCheckInputs = [ curl ];
  installCheckPhase = ''
    runHook preInstallCheck
    HOST=127.0.0.1 PORT=18345 $out/bin/${finalAttrs.pname} &
    server=$!
    trap 'kill $server 2>/dev/null || true' EXIT
    for i in $(seq 1 50); do
      curl -fsS http://127.0.0.1:18345/ > /dev/null 2>&1 && {
        echo "install check: server responded"; runHook postInstallCheck; exit 0; }
      kill -0 $server 2>/dev/null || break   # bare-bun help text exits immediately
      sleep 0.2
    done
    echo "install check: server never responded on :18345" >&2
    exit 1
  '';

  meta = {
    description = "SvelteKit demo compiled to a standalone Bun binary via bun2nix";
    mainProgram = finalAttrs.pname;
    platforms = lib.platforms.unix;
  };
})
```

### 3. `flake.nix` (mirrors the bun2nix react template's structure)

Pin `bun2nix` to a real git **tag** (npm may be ahead of tags — check `git tag` on the repo).
Consume its **overlay** so `pkgs.bun2nix` carries the `.mkDerivation` / `.fetchBunDeps` /
`.hook` passthru.

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";
    bun2nix.url = "github:nix-community/bun2nix?ref=2.1.0";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
    bun2nix.inputs.systems.follows = "systems";
  };
  nixConfig = {  # bun2nix is slow to compile from source
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
  };
  outputs = inputs:
    let
      eachSystem = inputs.nixpkgs.lib.genAttrs (import inputs.systems);
      pkgsFor = eachSystem (system: import inputs.nixpkgs {
        inherit system;
        overlays = [ inputs.bun2nix.overlays.default ];
      });
    in {
      packages = eachSystem (system: rec {
        svelte-bun2nix-demo = pkgsFor.${system}.callPackage ./default.nix { };
        default = svelte-bun2nix-demo;
      });
      apps = eachSystem (system: rec {
        svelte-bun2nix-demo = {
          type = "app";
          program = "${inputs.self.packages.${system}.svelte-bun2nix-demo}/bin/svelte-bun2nix-demo";
        };
        default = svelte-bun2nix-demo;
      });
      # Reuse the already-built package; don't re-callPackage without the bun2nix overlay.
      overlays.default = _final: prev: {
        svelte-bun2nix-demo = inputs.self.packages.${prev.stdenv.hostPlatform.system}.svelte-bun2nix-demo;
      };
      nixosModules.default = { config, lib, pkgs, ... }:
        let cfg = config.services.svelte-bun2nix-demo; in {
          options.services.svelte-bun2nix-demo = {
            enable = lib.mkEnableOption "the SvelteKit bun2nix demo server";
            package = lib.mkOption {
              type = lib.types.package;
              default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.svelte-bun2nix-demo;
            };
            host = lib.mkOption { type = lib.types.str; default = "0.0.0.0"; };
            port = lib.mkOption { type = lib.types.port; default = 3000; };
            openFirewall = lib.mkOption { type = lib.types.bool; default = false; };
          };
          config = lib.mkIf cfg.enable {
            systemd.services.svelte-bun2nix-demo = {
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];
              environment = { HOST = cfg.host; PORT = toString cfg.port; };
              serviceConfig = {
                ExecStart = lib.getExe cfg.package;   # relies on meta.mainProgram
                DynamicUser = true;
                Restart = "on-failure";
                ProtectSystem = "strict";
                ProtectHome = true;
                PrivateTmp = true;
                NoNewPrivileges = true;
              };
            };
            networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
          };
        };
      devShells = eachSystem (system: {
        default = pkgsFor.${system}.mkShell {
          packages = with pkgsFor.${system}; [ bun bun2nix ];
          shellHook = "bun install --frozen-lockfile";
        };
      });
    };
}
```

The `svelte-adapter-bun` server honors `HOST`, `PORT`, `SOCKET_PATH`, `BODY_SIZE_LIMIT`,
`IDLE_TIMEOUT` env vars at runtime — the module just sets `HOST`/`PORT`.

## Verify (always do all of these)

```sh
git add -A
nix build
# 1. runtime closure is clean — expect only the package + ICU, nothing dev:
nix path-info -r ./result | grep -iE 'node_modules|vite|svelte|typescript|bun2nix' || echo clean
# 2. SSR *and* static assets both work (the import.meta.dir bug only breaks assets):
PORT=3222 ./result/bin/<pname> &
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:3222/            # 200 (SSR)
curl -s http://localhost:3222/ | grep -oE '/_app/immutable/[^"]+\.js' | head -1  # grab a chunk
curl -s -o /dev/null -w '%{http_code}\n' "http://localhost:3222/<chunk>"   # 200 <- the real test
```

If SSR is `200` but the `/_app/immutable/*` chunk is `404`, the `import.meta.dir` rewrite didn't
apply — check the `substituteInPlace` target/string.

## Pitfalls checklist

- **Binary prints bun's CLI help / service exits 0 immediately** → fixupPhase stripped the
  embedded module graph. Use `bun2nix.mkDerivation` without a `buildPhase` override
  (`dontFixup = true` by default), or set `dontFixup = true;` explicitly. The HTTP install
  check catches this at build time.
- **Don't override `buildPhase`** → put the vite build in `preBuild` and the compile in
  `bunBuildFlags`; a custom `buildPhase` silently re-enables fixup in mkDerivation.
- **Assets 404 in the binary** → the `import.meta.dir` rewrite; don't forget to `cp` the assets
  into `$out/share/<pname>`.
- **`substituteInPlace ... --replace-fail`** errors loudly if the pattern is missing (good — a
  silent no-op would ship a broken binary). Use `--replace-fail`, not `--replace-quiet`.
- **New files invisible to `nix build`** → `git add` first (flakes read tracked files only).
- **`lib.getExe` needs `meta.mainProgram`** → set it, or the module's `ExecStart` fails to eval.
- **bun2nix pin** → pin a version that exists as a **git tag**; the npm package version can be
  ahead of the newest tag.
- **Darwin build flakiness** → `bunInstallFlags = [ "--linker=hoisted" "--backend=copyfile" ]`.
