{ pkgs, obeliskLib, nix-haskell-compilers, ... }:

let
    # A module whose config applies on darwin only. The system is config, so
    # it cannot choose what is imported; it can only guard what an import
    # defines.
    onDarwin = module: { config, lib, pkgs, ... }@args: {
      config = lib.mkIf (lib.hasSuffix "-darwin" config.system)
        (module args).config;
    };

in {

  # The nixpkgs driver has no wasm compiler of its own. The ghc-wasm-meta
  # bindist gives it one. The haskell.nix driver builds its own, but that
  # compiler is not in the binary caches for darwin and builds from source
  # for hours, so on darwin it takes the bindist too. Each series matches
  # that driver's own compiler.
  imports = [
    (import "${nix-haskell-compilers}/ghc-wasm-meta" {
      flavour = "9.12";
      drivers = [ "nixpkgs" ];
    })
    (onDarwin (import "${nix-haskell-compilers}/ghc-wasm-meta" {
      flavour = "9.14";
      drivers = [ "haskell-nix" ];
    }))
  ];

  name = "obelisk-skeleton";
  src = ./.;

  inherit (obeliskLib) source-repository-packages;

  obelisk.static.path = import ./static { inherit pkgs; };
  # For projects without a build step, use:
  # obelisk.static.path = ./static/src;

  # Public config (common/ + frontend/) is bundled into the production server;
  # backend/ is never bundled (keep secrets out of the Nix store).
  obelisk.config.path = ./config;

  shell = {
    crossPlatforms = ps: with ps; [
      wasi32

      # To enable JS builds in `nix-shell`, uncomment ghcjs below and use:
      #   cabal build/repl/run backend -f js
      #   ob-run/ob-repl -f js
      # ghcjs
    ];
    withHoogle = true;
  };

}
