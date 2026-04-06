{
  description = "Fly.io infrastructure for gunk-dev apps";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flux.url = "github:gunk-dev/flux";
    gunk-web.url = "github:gunk-dev/gunk-web";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      flux,
      gunk-web,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        fluxAssets = flux.packages.${system}.default;
        webAssets = gunk-web.packages.${system}.default;

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

        webOciImage = pkgs.dockerTools.buildLayeredImage {
          name = "gunk-web";
          tag = "latest";
          contents = [
            pkgs.caddy
          ];
          extraCommands = ''
            mkdir -p srv/www
            cp ${webAssets}/index.html srv/www/index.html
            mkdir -p etc/caddy
            cp ${webAssets}/Caddyfile etc/caddy/Caddyfile
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
          web-oci-image = webOciImage;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.flyctl
            pkgs.cue
            pkgs.go
            pkgs.jq
            pkgs.skopeo
            pkgs.nixfmt
          ];
        };
      }
    );
}
