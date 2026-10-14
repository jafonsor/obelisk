{
  inputs = {
    self.submodules = true;

    obelisk.url = ./deps/obelisk;
    nix-haskell.follows = "obelisk/nix-haskell";

    nixpkgs.follows = "obelisk/nixpkgs";
    flake-compat.follows = "obelisk/flake-compat";
  };

  outputs = inputs@{ self, ... }:
    let nixpkgs = if inputs ? "nixpkgs" then inputs.nixpkgs else builtins.getFlake "nixpkgs";
        eachSystem = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
    in {
      legacyPackages = eachSystem (system:
        import ./default.nix { inherit system inputs; }
      );

      packages = eachSystem (system:
        let project = import ./default.nix { inherit system inputs; };
        in rec {
          default = haskell-nix;
          haskell-nix = project.haskell-nix.serverExe.wasm;
          nixpkgs = project.nixpkgs.serverExe.js;
        }
        # release.nix is obelisk's own test matrix: it imports obelisk's nix/
        # by relative path, so ob-init leaves it out of scaffolded projects.
        // nixpkgs.lib.optionalAttrs (builtins.pathExists ./release.nix) {
          release = import ./release.nix { inherit system inputs; };
        });

      devShells = eachSystem (system:
        let shells = import ./shell.nix { inherit system inputs; };
        in {
          default = shells.haskell-nix;
          inherit (shells) nixpkgs;
        });
    };

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nixcache.reflex-frp.org"
      "https://cache.iog.io"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "ryantrinkle.com-1:JJiAKaRv9mWgpVAz8dwewnZe0AzzEAzPkagE9SP5NWI=" # reflex-frp
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
    ];
    allow-import-from-derivation = "true";
  };
}
