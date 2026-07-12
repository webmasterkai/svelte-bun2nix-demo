{
  lib,
  stdenv,
  bun2nix,
  curl,
}:
# Build the SvelteKit demo into a single, standalone Bun binary.
#
# We use the `bun2nix` setup hook (rather than the simpler `bun2nix.mkDerivation`)
# because a SvelteKit build is two steps: first `vite build` emits a Bun server
# under `build/`, then we AOT-compile that server into one executable. All the dev
# tooling (vite, svelte, the adapter, typescript) is only needed at build time and
# is NOT part of the resulting binary's runtime closure.
stdenv.mkDerivation (finalAttrs: {
  pname = "svelte-bun2nix-demo";
  version = "0.0.1";

  src = ./.;

  nativeBuildInputs = [ bun2nix.hook ];
  nativeInstallCheckInputs = [ curl ];

  # Offline, reproducible Bun install cache built purely from ./bun.nix.
  bunDeps = bun2nix.fetchBunDeps {
    bunNix = ./bun.nix;
  };

  # The isolated linker (Bun's default) can trip up Vite/SvelteKit on Darwin;
  # fall back to the hoisted linker there as the bun2nix docs recommend.
  bunInstallFlags = lib.optionals stdenv.hostPlatform.isDarwin [
    "--linker=hoisted"
    "--backend=copyfile"
  ];

  # We drive the build ourselves, so disable the hook's default bun build/check.
  dontUseBunBuild = true;
  dontUseBunCheck = true;

  # `bun build --compile` appends the bundled module graph to the executable;
  # fixupPhase (strip/patchelf) discards it, leaving a bare `bun` that prints CLI
  # help. bun2nix's own mkDerivation defaults to dontFixup for the same reason.
  dontFixup = true;

  buildPhase = ''
    runHook preBuild

    # 1. Build the SvelteKit app -> build/ (Bun server entry + static client assets).
    bun run build

    # 2. Bake the absolute (Nix store) assets path into the server handler.
    #    Once AOT-compiled, `import.meta.dir` points at the virtual bunfs root, so
    #    the server would otherwise fail to locate its client/prerendered assets.
    assets="${placeholder "out"}/share/${finalAttrs.pname}"
    substituteInPlace build/handler.js \
      --replace-fail "import.meta.dir" "\"$assets\""

    # 3. AOT-compile the Bun server into a single self-contained binary.
    #    Only runtime imports are bundled - no dev/build dependencies.
    bun build \
      --compile \
      --minify \
      --sourcemap \
      build/index.js \
      --outfile ${finalAttrs.pname}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 ${finalAttrs.pname} $out/bin/${finalAttrs.pname}

    mkdir -p $out/share/${finalAttrs.pname}
    cp -r build/client $out/share/${finalAttrs.pname}/client
    if [ -d build/prerendered ]; then
      cp -r build/prerendered $out/share/${finalAttrs.pname}/prerendered
    fi

    runHook postInstall
  '';

  # Smoke-test the installed binary: a broken compile (e.g. fixup stripping the
  # embedded module graph) degrades into a bare `bun` CLI that exits 0, so
  # actually start the server and require an HTTP response.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    HOST=127.0.0.1 PORT=18345 $out/bin/${finalAttrs.pname} &
    server=$!
    trap 'kill $server 2>/dev/null || true' EXIT
    for i in $(seq 1 50); do
      if curl -fsS http://127.0.0.1:18345/ > /dev/null 2>&1; then
        echo "install check: server responded"
        runHook postInstallCheck
        exit 0
      fi
      # Bail early if the binary already exited (bare-bun help text exits 0).
      kill -0 $server 2>/dev/null || break
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
