{
  description = "Fly.io infrastructure for Flux (gunk-dev org)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flux.url = "github:gunk-dev/flux";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      flux,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        fluxAssets = flux.packages.${system}.default;

        caddyfile = ./apps/flux/Caddyfile;

        ociImage = pkgs.dockerTools.buildLayeredImage {
          name = "flux";
          tag = "latest";
          contents = [
            pkgs.caddy
          ];
          extraCommands = ''
            mkdir -p srv/www
            cp -r ${fluxAssets}/* srv/www/
            mkdir -p etc/caddy
            cp ${caddyfile} etc/caddy/Caddyfile
          '';
          config = {
            Cmd = [
              "${pkgs.caddy}/bin/caddy"
              "run"
              "--config"
              "/etc/caddy/Caddyfile"
              "--adapter"
              "caddyfile"
            ];
            ExposedPorts = {
              "8080/tcp" = { };
            };
          };
        };
      in
      {
        packages = {
          default = ociImage;
          oci-image = ociImage;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.flyctl
            pkgs.cue
            pkgs.skopeo
            pkgs.nixfmt
          ];
        };
      }
    );
}
