{
  description = "Fly.io infrastructure for gunk-dev apps";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flux.url = "github:gunk-dev/flux";
    gunk-web.url = "github:gunk-dev/gunk-web";
    balance.url = "github:gunk-dev/balance";
    the-valley.url = "github:gunk-dev/the-valley";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      flux,
      gunk-web,
      balance,
      the-valley,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        fluxAssets = flux.packages.${system}.default;
        webAssets = gunk-web.packages.${system}.default;
        balanceOciImage = balance.packages.${system}.oci-image;
        valley = the-valley.packages.${system};

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
            mkdir -p srv
            cp -r ${webAssets}/www/* srv/
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

        # The valley web edge on one Fly Machine: valley-web-edge runs
        # valley-web-receive and valley-web, each as its own user from
        # the-valley's image, over the volume at /var/lib/valley-web, and
        # exits when either exits. Its arguments go to the receiver. It
        # runs as root to hand a new volume, and the token file Fly
        # writes, to the receiver before it drops to the two users.
        valleyWebEdge = pkgs.writeShellApplication {
          name = "valley-web-edge";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.util-linux
          ];
          text = ''
            state=/var/lib/valley-web
            chown valley-web-receive:valley-web "$state"
            chmod 0750 "$state"
            # A new ext4 volume holds root's lost+found, and the receiver
            # walks the whole state directory to measure it.
            if [ -d "$state/lost+found" ]; then chown -R valley-web-receive:valley-web "$state/lost+found"; fi
            chmod 0755 /etc/valley-web
            chmod 0444 /etc/valley-web/verifiers
            chown valley-web-receive /etc/valley-web/token
            chmod 0400 /etc/valley-web/token
            # --reset-env keeps Fly's secrets, which it also sets in the
            # environment, from both programs.
            as() { setpriv --reuid="$1" --regid=valley-web --clear-groups --reset-env -- "''${@:2}"; }
            as valley-web-receive ${valley.valley-web-receive}/bin/valley-web-receive \
              --state "$state" --listen :8081 \
              --verifiers /etc/valley-web/verifiers --token-file /etc/valley-web/token "$@" &
            receiver=$!
            as valley-web ${valley.valley-web}/bin/valley-web --state "$state" --listen :8080 &
            web=$!
            trap 'kill -TERM "$receiver" "$web" 2>/dev/null' TERM INT
            wait -n || true
            kill -TERM "$receiver" "$web" 2>/dev/null || true
            wait
            exit 1
          '';
        };

        # valley-web answers 503 on every path until a first export is
        # active, and a smoke test wants 200: the image's default command
        # serves this export of no projects instead of the volume.
        valleyWebSmokeState = pkgs.runCommand "valley-web-smoke-state" { } ''
          mkdir -p $out/exports/1
          echo '{"schema":"valley-web-export/v1","collected":"1970-01-01T00:00:00Z","projects":[]}' \
            > $out/exports/1/export.json
          ln -s exports/1 $out/active
        '';

        valleyWebOciImage = pkgs.dockerTools.buildLayeredImage {
          name = "valley-web-edge";
          tag = "latest";
          fromImage = valley.valley-web-image;
          contents = [ valleyWebEdge ];
          config = {
            User = "0:0";
            WorkingDirectory = "/";
            Env = [ "PATH=/bin" ];
            Volumes."/var/lib/valley-web" = { };
            Cmd = [
              "${pkgs.util-linux}/bin/setpriv"
              "--reuid=valley-web"
              "--regid=valley-web"
              "--clear-groups"
              "--"
              "${valley.valley-web}/bin/valley-web"
              "--state"
              "${valleyWebSmokeState}"
              "--listen"
              ":8080"
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
          balance-oci-image = balanceOciImage;
          valley-web-oci-image = valleyWebOciImage;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.flyctl
            pkgs.cue
            pkgs.jq
            pkgs.skopeo
            pkgs.nixfmt
          ];
        };
      }
    );
}
