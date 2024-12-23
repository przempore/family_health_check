{
  inputs = {
    nixpkgs.url = "github:cachix/devenv-nixpkgs/rolling";
    systems.url = "github:nix-systems/default";
    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
    fenix.url = "github:nix-community/fenix";
    fenix.inputs = { nixpkgs.follows = "nixpkgs"; };
    rust-overlay.url = "github:oxalica/rust-overlay";

  };

  nixConfig = {
    extra-trusted-public-keys = "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = { self, nixpkgs, devenv, systems, rust-overlay, ... } @ inputs:
    let
      forEachSystem = nixpkgs.lib.genAttrs (import systems);
    in
    {
      packages = forEachSystem
        (system:
          let
            overlays = [ (import rust-overlay) ];
            pkgs = import nixpkgs {
              inherit system overlays;
            };
            rustToolchain = pkgs.rust-bin.nightly.latest.default.override {
              extensions = [ "rust-src" ];
              targets = [ "wasm32-unknown-unknown" "x86_64-unknown-linux-gnu" ];
            };

            backend = pkgs.rustPlatform.buildRustPackage {
              cargoLock = {
                lockFileContents = builtins.readFile ./Cargo.lock;
              };
              name = "backend";
              src = ./.;
              cargoBuildOptions = [ "-p backend" "--release" ];
              nativeBuildInputs = [ rustToolchain ];
              # buildPhase = ''
              #   cargo build -p backend --release
              # '';
            };

            frontend = pkgs.rustPlatform.buildRustPackage {
              cargoLock = {
                lockFileContents = builtins.readFile ./Cargo.lock;
              };
              name = "frontend";
              src = ./.;
              # cargoBuildOptions = [ "-p frontend" "--release" ];
              nativeBuildInputs = [ rustToolchain pkgs.trunk ];
              buildPhase = ''
                cargo build --target wasm32-unknown-unknown -p frontend
              '';
            };
          in
          {
            devenv-up = self.devShells.${system}.default.config.procfileScript;
            devenv-test = self.devShells.${system}.default.config.test;

            inherit backend frontend;

            backend-docker = pkgs.dockerTools.buildImage {
              name = "backend";
              tag = "latest";
              config = {
                Cmd = [ "${backend}/bin/backend" ];
                WorkingDir = "/app";
                ExposedPorts = { "3000/tcp" = { }; };
                Volumes = {
                  "/data" = { };
                };
              };

              runAsRoot = ''
                mkdir -p /data
              '';
            };

            # TODO: frontend-docker
            frontend-docker = pkgs.dockerTools.buildImage {
              name = "frontend";
              tag = "latest";
              config = {
                Cmd = [ "trunk" "serve" ];
                WorkingDir = "/app";
                ExposedPorts = { "3000/tcp" = { }; };
              };
              contents = [ frontend pkgs.trunk ];
            };

            # default = frontend;

          });

      devShells = forEachSystem
        (system:
          let
            pkgs = nixpkgs.legacyPackages.${system};
          in
          {
            default = devenv.lib.mkShell {
              inherit inputs pkgs;
              modules = [
                {
                  # https://devenv.sh/reference/options/
                  packages = [ pkgs.ffmpeg pkgs.pkg-config pkgs.clang pkgs.libclang.lib pkgs.trunk pkgs.leptosfmt ];

                  languages.rust = {
                    enable = true;
                    channel = "nightly";
                    targets = [ "wasm32-unknown-unknown" "x86_64-unknown-linux-gnu" ];
                  };

                  enterShell = ''
                    export LIBCLANG_PATH=${pkgs.libclang.lib}/lib
                    cargo --version
                    trunk --version
                    leptosfmt --version
                  '';
                }
              ];
            };
          });

      formatter = forEachSystem
        (system:
          let
            pkgs = import nixpkgs { inherit system; };
          in
          pkgs.nixpkgs-fmt);
    };
}
