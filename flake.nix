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
        # the-valley's image, over the store whose descriptor is
        # /var/lib/valley-web/store on the volume, and exits when either
        # exits. Its arguments go to the receiver. It runs as root to hand
        # a new volume, and the token file Fly writes, to the receiver
        # before it drops to the two users.
        valleyWebEdge = pkgs.writeShellApplication {
          name = "valley-web-edge";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.util-linux
          ];
          text = ''
            # The volume is the receiver's, and valley-web reads and
            # searches it through the group. The receiver writes the
            # descriptor here and its payloads in v2/ beside it, and
            # nothing else on the volume.
            state=/var/lib/valley-web
            store=$state/store
            chown valley-web-receive:valley-web "$state"
            chmod 0750 "$state"
            # A new ext4 volume holds root's lost+found, which goes to the
            # receiver with the rest of the volume.
            if [ -d "$state/lost+found" ]; then chown -R valley-web-receive:valley-web "$state/lost+found"; fi
            chmod 0755 /etc/valley-web
            chmod 0444 /etc/valley-web/verifiers
            chown valley-web-receive /etc/valley-web/token
            chmod 0400 /etc/valley-web/token
            # --reset-env keeps Fly's secrets, which it also sets in the
            # environment, from both programs.
            as() { setpriv --reuid="$1" --regid=valley-web --clear-groups --reset-env -- "''${@:2}"; }
            as valley-web-receive ${valley.valley-web-receive}/bin/valley-web-receive \
              --state "$store" --listen :8081 \
              --verifiers /etc/valley-web/verifiers --token-file /etc/valley-web/token "$@" &
            receiver=$!
            # valley-web opens only a store that exists, and the receiver
            # makes a new one on its first start, writing the descriptor
            # last.
            until [ -f "$store" ]; do
              kill -0 "$receiver" 2>/dev/null || exit 1
              sleep 0.1
            done
            as valley-web ${valley.valley-web}/bin/valley-web --state "$store" --listen :8080 &
            web=$!
            trap 'kill -TERM "$receiver" "$web" 2>/dev/null' TERM INT
            wait -n || true
            kill -TERM "$receiver" "$web" 2>/dev/null || true
            wait
            exit 1
          '';
        };

        # valley-web answers 503 on every path until its store holds an
        # authorization and an active export, and a smoke test wants 200:
        # the image's default command serves this store instead of the
        # volume. It holds what valley-web reads of a receiver's store
        # once the receiver has admitted an authorization that names no
        # project and activated an export of none. valley-web reads the
        # stored authorization without checking its signature, which the
        # receiver checked, so it is signed with the-valley's test key
        # (web/export/exporttest), which no receiver trusts.
        valleyWebSmokeState =
          pkgs.runCommand "valley-web-smoke-state"
            {
              nativeBuildInputs = [ pkgs.openssl ];
            }
            ''
              mkdir -p $out/v2/generations/1/repos
              echo 'the-valley/web-store/v2' > $out/store
              echo '{"schema":"valley-web-export/v2","collected":"1970-01-01T00:00:00Z","projects":[]}' \
                > $out/v2/generations/1/export.json
              echo 1 > $out/v2/high-water
              ln -s generations/1 $out/v2/current
              touch $out/v2/serving.lock

              # The key is the PKCS #8 prefix of an Ed25519 key and the
              # test key's seed.
              { printf '\x30\x2e\x02\x01\x00\x30\x05\x06\x03\x2b\x65\x70\x04\x22\x04\x20'
                printf 'the-valley web export test key!!'
              } > key.der
              openssl pkey -inform DER -in key.der -pubout -outform DER | tail -c 32 > public
              printf '%s\n' \
                the-valley/web-authorization/v1 \
                'instance smoke' \
                'destination smoke' \
                'sequence 1' \
                'checked 1970-01-01T00:00:00Z' \
                > text
              # A signature line is the signer's name and, in base64, the
              # first four bytes of SHA-256 over the name, a newline, the
              # algorithm byte and the public key, then the signature.
              { printf 'smoke\n\x01'; cat public; } | openssl dgst -sha256 -binary | head -c 4 > signature
              openssl pkeyutl -sign -inkey key.der -keyform DER -rawin -in text >> signature
              { cat text; echo; echo "— smoke $(base64 -w0 signature)"; } > $out/v2/authorization
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
              "${valleyWebSmokeState}/store"
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
