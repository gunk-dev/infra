# infra

Fly.io infrastructure for [Flux](https://github.com/patflynn/flux), [Balance](https://github.com/patflynn/balance), and [Web](https://github.com/gunk-dev/gunk-web) (gunk.dev), managed with CUE and Nix.

Deploy workflows delegate to reusable workflows in [gunk-dev/armstrong](https://github.com/gunk-dev/armstrong). CUE schemas (`#FlyApp`, `#DNSRecord`, etc.) live in `cue.mod/pkg/gunk.dev/armstrong/schema/`.

## Prerequisites

- [Nix](https://nixos.org/) with flakes enabled

## Dev shell

```sh
nix develop
```

Provides: `flyctl`, `cue`, `go`, `jq`, `skopeo`, `nixfmt`

## Apps

### Flux

Static PWA served by Caddy on port 8080. The OCI image is built in this repo via `nix build .#oci-image`.

### Balance

React + Fastify monorepo app serving both API endpoints and static files on port 8080. The OCI image is built in the [balance repo](https://github.com/patflynn/balance) and passed to deploy workflows via `client_payload.image`.

### Web

Static site for gunk.dev served by Caddy on port 8080. The OCI image is built in the [gunk-web repo](https://github.com/gunk-dev/gunk-web) and passed to deploy workflows via `inputs.image`. Serves the apex domain (`gunk.dev`) and `www.gunk.dev`.

## DNS Management

DNS records for `gunk.dev` are declared in CUE (`dns/gunk.dev.cue`) and synced to [Porkbun](https://porkbun.com) via a Go CLI tool.

### Record definitions

All records are defined in `dns/gunk.dev.cue` using the `#DNSRecord` schema from `cue.mod/pkg/gunk.dev/armstrong/schema/dns.cue`. This includes email (MX, SPF, DKIM) and app CNAME records.

```sh
# Validate DNS config
cue vet ./dns

# Export as JSON (this is what the sync tool reads)
cue export ./dns --out json
```

### Syncing records

The `cmd/dns` tool reads the CUE export and converges Porkbun to match:

```sh
# Dry-run: see what would change (requires API keys)
cue export ./dns --out json | go run ./cmd/dns sync

# With pruning (deletes records not in CUE, skips NS/SOA/preview-*)
cue export ./dns --out json | go run ./cmd/dns sync --prune
```

Requires `PORKBUN_API_KEY` and `PORKBUN_SECRET_KEY` environment variables.

On push to `main` (when `dns/`, `cmd/dns/`, or `cue.mod/pkg/gunk.dev/armstrong/schema/dns.cue` change), the DNS sync workflow runs automatically.

### Preview DNS records

Preview CNAME records (`preview-{pr}.{app}.gunk.dev`) are managed automatically by the preview deploy/cleanup workflows. To manage manually:

```sh
# Create: preview-42.flux.gunk.dev -> flux-preview-42.fly.dev
go run ./cmd/dns preview create flux 42

# Delete
go run ./cmd/dns preview delete flux 42
```

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

## CI

A CI workflow runs on every pull request and push to main:

- **lint**: `nixfmt --check` and `nix flake check`
- **validate-cue**: validates CUE schemas and verifies export for all environments (flux, balance, and web)
- **build**: builds the OCI image (flux)
- **zizmor**: security lints GitHub Actions workflows

### Flux deployments

Triggered from the [flux repo](https://github.com/patflynn/flux) via `repository_dispatch`:

- **Preview**: `flux-preview` event on PR open/sync — deploys a per-PR preview app, comments the URL on the PR
- **Preview cleanup**: `flux-preview-cleanup` event on PR close — destroys the preview app
- **Staging**: `flux-staging` event on merge to main — triggers a flake.lock update PR with auto-merge, which deploys to `flux-staging` on merge
- **Production**: Manual `workflow_dispatch` in this repo

### Balance deployments

Triggered from the [balance repo](https://github.com/patflynn/balance) via `repository_dispatch`. The balance repo builds its own OCI image and passes the image reference in `client_payload.image`.

- **Preview**: `balance-preview` event on PR open/sync — deploys a per-PR preview app, comments the URL on the PR
- **Preview cleanup**: `balance-preview-cleanup` event on PR close — destroys the preview app
- **Staging**: `balance-staging` event on merge to main — triggers a flake.lock update PR with auto-merge, which deploys to `balance-staging` on merge
- **Production**: Manual `workflow_dispatch` in this repo

### Web deployments

Triggered from the [gunk-web repo](https://github.com/gunk-dev/gunk-web) via `repository_dispatch`. The gunk-web repo builds its own OCI image.

- **Preview**: `web-preview` event on PR open/sync — deploys a per-PR preview app, comments the URL on the PR
- **Preview cleanup**: `web-preview-cleanup` event on PR close — destroys the preview app
- **Staging**: `web-staging` event on merge to main — triggers a flake.lock update PR with auto-merge, which deploys to `gunk-web-staging` on merge
- **Production**: Manual `workflow_dispatch` in this repo

### Secrets

Deploy workflows read `FLY_API_TOKEN` from GitHub **environments** (preview, staging, production), not repo-level secrets.

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
