{
  description = "SvelteKit demo compiled to a standalone Bun binary with bun2nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";

    bun2nix.url = "github:nix-community/bun2nix?ref=2.1.0";
    bun2nix.inputs.nixpkgs.follows = "nixpkgs";
    bun2nix.inputs.systems.follows = "systems";
  };

  # Pull the (slow-to-compile) bun2nix binary from the nix-community cache.
  nixConfig = {
    extra-substituters = [ "https://nix-community.cachix.org" ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  outputs =
    inputs:
    let
      eachSystem = inputs.nixpkgs.lib.genAttrs (import inputs.systems);

      pkgsFor = eachSystem (
        system:
        import inputs.nixpkgs {
          inherit system;
          # The bun2nix overlay puts `bun2nix` (with its .hook / .fetchBunDeps
          # passthru helpers) into pkgs so default.nix can be callPackage'd.
          overlays = [ inputs.bun2nix.overlays.default ];
        }
      );
    in
    {
      packages = eachSystem (system: rec {
        svelte-bun2nix-demo = pkgsFor.${system}.callPackage ./default.nix { };
        default = svelte-bun2nix-demo;
      });

      # `nix run` starts the compiled Bun server.
      apps = eachSystem (system: rec {
        svelte-bun2nix-demo = {
          type = "app";
          program = "${inputs.self.packages.${system}.svelte-bun2nix-demo}/bin/svelte-bun2nix-demo";
        };
        default = svelte-bun2nix-demo;
      });

      # Overlay so downstream flakes can `pkgs.svelte-bun2nix-demo` after adding it.
      overlays.default = _final: prev: {
        svelte-bun2nix-demo =
          inputs.self.packages.${prev.stdenv.hostPlatform.system}.svelte-bun2nix-demo;
      };

      # NixOS module: a systemd service that runs the demo. Import it and set
      # `services.svelte-bun2nix-demo.enable = true;`.
      nixosModules.default =
        { config, lib, pkgs, ... }:
        let
          cfg = config.services.svelte-bun2nix-demo;
        in
        {
          options.services.svelte-bun2nix-demo = {
            enable = lib.mkEnableOption "the SvelteKit bun2nix demo server";

            package = lib.mkOption {
              type = lib.types.package;
              default = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.svelte-bun2nix-demo;
              defaultText = lib.literalMD "the flake's `svelte-bun2nix-demo` package";
              description = "The svelte-bun2nix-demo package to run.";
            };

            host = lib.mkOption {
              type = lib.types.str;
              default = "0.0.0.0";
              description = "Address the server binds to.";
            };

            port = lib.mkOption {
              type = lib.types.port;
              default = 3000;
              description = "Port the server listens on.";
            };

            openFirewall = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether to open {option}`port` in the firewall.";
            };
          };

          config = lib.mkIf cfg.enable {
            systemd.services.svelte-bun2nix-demo = {
              description = "SvelteKit bun2nix demo";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];
              environment = {
                HOST = cfg.host;
                PORT = toString cfg.port;
              };
              serviceConfig = {
                ExecStart = lib.getExe cfg.package;
                DynamicUser = true;
                Restart = "on-failure";
                # Hardening - the binary is fully self-contained.
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
          packages = with pkgsFor.${system}; [
            bun
            bun2nix
          ];

          shellHook = ''
            bun install --frozen-lockfile
          '';
        };
      });
    };
}
