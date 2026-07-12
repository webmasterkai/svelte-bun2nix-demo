{
  lib,
  stdenv,
  bun2nix,
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
  # fixupPhase's strip would discard it, leaving a bare `bun` that prints CLI help.
  dontStrip = true;

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

  meta = {
    description = "SvelteKit demo compiled to a standalone Bun binary via bun2nix";
    mainProgram = finalAttrs.pname;
    platforms = lib.platforms.unix;
  };
})
