# infra

Fly.io infrastructure for [Flux](https://github.com/patflynn/flux), [Balance](https://github.com/patflynn/balance), [Web](https://github.com/gunk-dev/gunk-web) (gunk.dev), and the [valley](https://github.com/gunk-dev/the-valley) web edge, managed with CUE and Nix.

Deploy workflows delegate to reusable workflows in [gunk-dev/armstrong](https://github.com/gunk-dev/armstrong). CUE schemas (`#FlyApp`, `#DNSRecord`, etc.) live in `cue.mod/pkg/gunk.dev/armstrong/schema/`.

## Prerequisites

- [Nix](https://nixos.org/) with flakes enabled

## Dev shell

```sh
nix develop
```

Provides: `flyctl`, `cue`, `jq`, `skopeo`, `nixfmt`

## Apps

### Flux

Static PWA served by Caddy on port 8080. The OCI image is built in this repo via `nix build .#oci-image`.

### Balance

React + Fastify monorepo app serving both API endpoints and static files on port 8080. The OCI image is built in the [balance repo](https://github.com/patflynn/balance) and passed to deploy workflows via `client_payload.image`.

### Web

Static site for gunk.dev served by Caddy on port 8080. The OCI image is built in the [gunk-web repo](https://github.com/gunk-dev/gunk-web) and passed to deploy workflows via `inputs.image`. Serves the apex domain (`gunk.dev`) and `www.gunk.dev`.

### Valley web

The-valley's read-only web edge, in `yyz`. The valley host pushes a signed authorization and signed exports to `valley-web-receive` over HTTPS on port 8443, and `valley-web` serves the projects the authorization lets anyone read on 80/443; the edge never connects back. The image, `nix build .#valley-web-oci-image`, derives from the-valley's `valley-web-image`. On Fly, its `valley-web-edge` command runs both programs on one Machine, each as its own user, over the store whose descriptor is `/var/lib/valley-web/store` on the volume, and exits when either exits. The receiver keeps the store's payloads in `v2/` beside the descriptor, and writes nothing else on the volume. Its default command serves an empty store on port 8080, for smoke tests: valley-web answers 503 until its store holds a signed authorization and an active export.

The receiver reads the bearer token from the `VALLEY_WEB_RECEIVER_TOKEN` secret (base64-encoded, as `[[files]]` requires) and the publisher's verifier line from `apps/valley-web/verifiers`. It refuses to start while that file holds no verifier line.

## DNS Management

DNS records are declared in CUE under `dns/` and synced to [Porkbun](https://porkbun.com) via the DNS tool in [gunk-dev/armstrong](https://github.com/gunk-dev/armstrong).

### Record definitions

Each zone lives in its own directory, `dns/<zone>/`, which is a CUE package `dns` declaring a `domain` and a `records` list conforming to the `#DNSRecord` schema from `cue.mod/pkg/gunk.dev/armstrong/schema/dns.cue`:

| Zone | Directory | Contents |
| --- | --- | --- |
| `gunk.dev` | `dns/gunk.dev/gunk.dev.cue` | email (MX, SPF, DKIM) and app CNAME records, plus apex `A`/`AAAA` |
| `broken.dev` | `dns/broken.dev/broken.dev.cue` | apex and `www` `A` records pointing at the Google Cloud load balancer |

Records leave `ttl` unset to take the schema default (600).

```sh
# Validate every zone
cue vet ./dns/...

# Export one zone as JSON — the trailing slash is required, or cue reads
# "gunk.dev" as a filename and rejects the ".dev" extension
cue export ./dns/gunk.dev/ --out json

# Export every zone as the combined array the sync tool consumes
for zone in dns/*/; do cue export "./${zone}" --out json; done | jq -s .
```

### Adding a zone

1. Add a `dns/<zone>/` directory containing a CUE package `dns` with `domain` and `records`. CI and the sync workflow pick it up automatically — no workflow edits needed.
2. Enable **API Access** on that domain in the Porkbun dashboard. This is a per-domain toggle: the shared `PORKBUN_API_KEY` is useless on a domain that has not enabled it, and the sync will fail for that zone.

The zone must also exist at Porkbun before a sync can converge it, and pointing the domain's nameservers at Porkbun at its current registrar is a separate manual step.

### Syncing records

On push to `main` (when `dns/**` changes), the DNS sync workflow calls armstrong's reusable workflow, which vets and exports each zone directory in sorted order and syncs them all in one run. The sync tool rejects duplicate domains before making any API call.

Preview CNAME records (`preview-{pr}.{app}.gunk.dev`) are managed automatically by the preview deploy/cleanup workflows.

## Build OCI image locally (Flux only)

```sh
nix build .#oci-image
# Produces result -> a Docker archive tarball
```

## CUE config

All Fly.io configuration lives in CUE. `fly.toml` is never checked in — it's generated at deploy time.

```sh
# Validate all environments for an app
cue vet ./apps/flux/...
cue vet ./apps/balance/...
cue vet ./apps/web/...
cue vet ./apps/valley-web -t prod

# Export a specific environment
cue export ./apps/flux -t staging -e staging --out toml
cue export ./apps/balance -t staging -e staging --out toml
cue export ./apps/web -t staging -e staging --out toml
```

Preview apps accept an `appName` tag for dynamic app naming:

```sh
cue export ./apps/flux -t preview -t appName=flux-preview-42 -e preview --out toml
cue export ./apps/balance -t preview -t appName=balance-preview-42 -e preview --out toml
cue export ./apps/web -t preview -t appName=gunk-web-preview-42 -e preview --out toml
```

### Environments

#### Flux

| Environment | App name | auto_stop | min_machines |
|---|---|---|---|
| preview | `flux-preview-{pr}` | suspend | 0 |
| staging | `flux-staging` | suspend | 1 |
| prod | `flux-prod` | off | 1 |

#### Balance

| Environment | App name | auto_stop | min_machines |
|---|---|---|---|
| preview | `balance-preview-{pr}` | suspend | 0 |
| staging | `balance-staging` | suspend | 1 |
| prod | `balance-prod` | off | 1 |

#### Web

| Environment | App name | auto_stop | min_machines |
|---|---|---|---|
| preview | `gunk-web-preview-{pr}` | suspend | 0 |
| staging | `gunk-web-staging` | suspend | 1 |
| prod | `gunk-web-prod` | off | 1 |

#### Valley web

| Environment | App name | auto_stop | min_machines |
|---|---|---|---|
| prod | `valley-web-prod` | off | 1 |

## CI

A CI workflow runs on every pull request and push to main:

- **lint**: `nixfmt --check` and `nix flake check`
- **validate-cue**: validates CUE schemas and verifies export for all environments (flux, balance, web, valley-web)
- **build**: builds OCI images (flux, gunk-web, balance, valley-web-edge) and runs smoke tests
- **zizmor**: security lints GitHub Actions workflows

### Flux deployments

Triggered from the [flux repo](https://github.com/patflynn/flux) via `repository_dispatch`:

- **Preview**: `flux-preview` event on PR open/sync — deploys a per-PR preview app, comments the URL on the PR
- **Preview cleanup**: `flux-preview-cleanup` event on PR close — destroys the preview app
- **Staging**: `flux-staging` event on merge to main — triggers a flake.lock update PR with auto-merge, which deploys to `flux-staging` on merge
- **Prod**: Manual `workflow_dispatch` in this repo

### Balance deployments

Triggered from the [balance repo](https://github.com/patflynn/balance) via `repository_dispatch`. The balance repo builds its own OCI image and passes the image reference in `client_payload.image`.

- **Preview**: `balance-preview` event on PR open/sync — deploys a per-PR preview app, comments the URL on the PR
- **Preview cleanup**: `balance-preview-cleanup` event on PR close — destroys the preview app
- **Staging**: `balance-staging` event on merge to main — triggers a flake.lock update PR with auto-merge, which deploys to `balance-staging` on merge
- **Prod**: Manual `workflow_dispatch` in this repo

### Web deployments

Triggered from the [gunk-web repo](https://github.com/gunk-dev/gunk-web) via `repository_dispatch`. The gunk-web repo builds its own OCI image.

- **Preview**: `web-preview` event on PR open/sync — deploys a per-PR preview app, comments the URL on the PR
- **Preview cleanup**: `web-preview-cleanup` event on PR close — destroys the preview app
- **Staging**: `web-staging` event on merge to main — triggers a flake.lock update PR with auto-merge, which deploys to `gunk-web-staging` on merge
- **Prod**: Manual `workflow_dispatch` in this repo

### Valley web deployments

- **Prod**: Manual `workflow_dispatch` in this repo. There is no staging or preview.

### Secrets

Deploy workflows read `FLY_API_TOKEN` from GitHub environments (**preview**, **staging**, **prod**), not repo-level secrets.

Preview and update workflows use a GitHub App for cross-repo PR comments and auto-merge PRs. `APP_ID` and `APP_PRIVATE_KEY` are stored in the **preview** and **automation** environments respectively.

DNS workflows read `PORKBUN_API_KEY` and `PORKBUN_SECRET_KEY` from the `dns` environment.

### Flux repo setup

The flux repo needs to send `repository_dispatch` events to this repo:

```yaml
# On PR open/synchronize
- uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.INFRA_DISPATCH_TOKEN }}
    repository: gunk-dev/infra
    event-type: flux-preview
    client-payload: '{"pr_number": "${{ github.event.pull_request.number }}"}'

# On PR close
- uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.INFRA_DISPATCH_TOKEN }}
    repository: gunk-dev/infra
    event-type: flux-preview-cleanup
    client-payload: '{"pr_number": "${{ github.event.pull_request.number }}"}'

# On merge to main
- uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.INFRA_DISPATCH_TOKEN }}
    repository: gunk-dev/infra
    event-type: flux-staging
```

### Balance repo setup

The balance repo needs to send `repository_dispatch` events to this repo, including the built image reference:

```yaml
# On PR open/synchronize
- uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.INFRA_DISPATCH_TOKEN }}
    repository: gunk-dev/infra
    event-type: balance-preview
    client-payload: '{"pr_number": "${{ github.event.pull_request.number }}", "image": "registry.fly.io/balance-preview-${{ github.event.pull_request.number }}:${{ github.sha }}"}'

# On PR close
- uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.INFRA_DISPATCH_TOKEN }}
    repository: gunk-dev/infra
    event-type: balance-preview-cleanup
    client-payload: '{"pr_number": "${{ github.event.pull_request.number }}"}'

# On merge to main
- uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.INFRA_DISPATCH_TOKEN }}
    repository: gunk-dev/infra
    event-type: balance-staging
    client-payload: '{"image": "registry.fly.io/balance-staging:${{ github.sha }}"}'
```

Requires an `INFRA_DISPATCH_TOKEN` secret (PAT with `repo` scope on `gunk-dev/infra`).
