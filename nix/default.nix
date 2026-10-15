{ system ? builtins.currentSystem
, inputs ? import ../inputs.nix
, pkgs ? import inputs.nixpkgs { inherit system; }
}:

let nix-haskell = import inputs.nix-haskell { inherit system pkgs inputs; };

    lib = import ./lib.nix { inherit system inputs pkgs; };

    module = import ./module.nix;

in lib // {
  inherit module;
  inherit (lib) extraCabalProject serverModule;

  project = userModule:
    let eval = nix-haskell {
          imports = [
            module
            userModule
          ];
        };

        outputs = { proj, targets, defaultTarget }:
          let serverExe = pkgs.lib.genAttrs targets (target:
                lib.mkServerExe { inherit proj target; });
          in proj // {
            exe = pkgs.lib.genAttrs targets (target:
              lib.perDriver proj.config lib.backendExe
                (proj.override { obelisk.frontend.target = target; }));

            inherit serverExe;

            containerImage = pkgs.lib.genAttrs targets (target:
              lib.mkContainerImage { inherit proj target; });

            server = { exe ? serverExe.${defaultTarget}, ... }@args:
              let nixos = import (eval.pkgs.path + /nixos);
              in nixos {
                inherit system;
                configuration = {
                  imports = [ lib.serverModule ];
                  services.obelisk = { enable = true; } // args;
                };
              };
          };

        # The nixpkgs driver has no wasm compiler of its own. It builds the
        # target only where the project supplies one.
        nixpkgsTargets = [ "js" ]
          ++ pkgs.lib.optional (eval.config.nixpkgs.pkgsCross ? wasi32) "wasm";

    in {
      config = eval.config;
      pkgs = eval.pkgs;
      inherit (lib) serverModule;

      haskell-nix = outputs {
        proj = eval.haskell-nix.project;
        targets = [ "wasm" "js" ];
        defaultTarget = "wasm";
      } // {
        # A hack, for the dev shell only: the shell comes from a copy of the
        # project whose backend library does not link the assets into its
        # data dir (obelisk.backend.linkAssets, the preBuild/postInstall of
        # lib.nix's backendDataOverride).
        #
        # Building the shell evaluates the backend's derivation (shellFor
        # walks it for dependencies), haskell.nix checks each hook for
        # emptiness, and nix strings are strict, so the hook's asset paths
        # are forced. Those assets are listed from the built frontend at
        # evaluation time (assets.nix reads the directory), so every
        # frontend change made loading the shell compile the production
        # frontend, only to throw it away. Overriding the hooks with
        # mkForce is not enough: the module system still evaluates the
        # definitions it overrides, so the hooks must not be defined.
        #
        # This only works because nix does not build the backend in
        # development: ob-run builds it with cabal and links the assets
        # itself. Anything that builds the backend with nix (exe,
        # serverExe, containerImage) must keep using `proj`, or it would
        # miss what those hooks do. The hooks add nothing to the shell's
        # dependencies, which come from the components' depends, inputs and
        # tools.
        shell = (eval.haskell-nix.project.override {
          obelisk.backend.linkAssets = false;
        }).shell;
      };

      nixpkgs = outputs {
        proj = eval.nixpkgs.project.override { obelisk.driver = "nixpkgs"; };
        targets = nixpkgsTargets;
        defaultTarget = "js";
      };
    };
}
