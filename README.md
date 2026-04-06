# infra

Fly.io infrastructure for [Flux](https://github.com/patflynn/flux) and [Balance](https://github.com/patflynn/balance), managed with CUE and Nix.

## Prerequisites

- [Nix](https://nixos.org/) with flakes enabled

## Dev shell

```sh
nix develop
```

Provides: `flyctl`, `cue`, `skopeo`, `nixfmt`, `jq`, `curl`

## Apps

### Flux

Static PWA served by Caddy on port 8080. The OCI image is built in this repo via `nix build .#oci-image`.

### Balance

React + Fastify monorepo app serving both API endpoints and static files on port 8080. The OCI image is built in the [balance repo](https://github.com/patflynn/balance) and passed to deploy workflows via `client_payload.image`.

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

# Export a specific environment
cue export ./apps/flux -t staging -e staging --out toml
cue export ./apps/balance -t staging -e staging --out toml
```

Preview apps accept an `appName` tag for dynamic app naming:

```sh
cue export ./apps/flux -t preview -t appName=flux-preview-42 -e preview --out toml
cue export ./apps/balance -t preview -t appName=balance-preview-42 -e preview --out toml
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

## DNS

DNS records for `gunk.dev` are managed via CUE definitions in `dns/` and synced to [Porkbun](https://porkbun.com/) using their REST API.

### Record definitions

Records are defined in `dns/gunk.dev.cue` using the `schema.#DNSRecord` type. Each app has individual CNAME records per environment:

```
{type: "CNAME", name: "flux",           content: "flux-prod.fly.dev"}
{type: "CNAME", name: "staging.flux",    content: "flux-staging.fly.dev"}
```

This produces domains like `flux.gunk.dev` (prod) and `staging.flux.gunk.dev` (staging).

### Validate and export

```sh
cue vet ./dns
cue export ./dns --out json
```

### Manual sync

```sh
export PORKBUN_API_KEY="..."
export PORKBUN_SECRET_KEY="..."
./scripts/dns-sync.sh          # create/update only
./scripts/dns-sync.sh --prune  # also delete records not in CUE
```

The `--prune` flag skips NS, SOA, bare-domain records, and preview records.

### Preview DNS

Preview DNS records are created and deleted automatically by the deploy workflows. They follow the pattern `preview-{pr}.{app}.gunk.dev` (e.g., `preview-42.flux.gunk.dev`).

To manage manually:

```sh
./scripts/dns-preview.sh create flux 42   # creates preview-42.flux.gunk.dev
./scripts/dns-preview.sh delete flux 42   # deletes it
```

### CI/CD

- On push to `main` when `dns/` changes, the DNS sync workflow reconciles records via the Porkbun API.
- Preview deploy workflows create DNS records; cleanup workflows delete them.

### Secrets

DNS workflows require `PORKBUN_API_KEY` and `PORKBUN_SECRET_KEY` in the GitHub **production** and **preview** environments.

## Deploy

```sh
# Preview (requires PR number)
./scripts/deploy.sh flux preview 42
./scripts/deploy.sh balance preview 42

# Staging
./scripts/deploy.sh flux staging
./scripts/deploy.sh balance staging

# Production
./scripts/deploy.sh flux prod
./scripts/deploy.sh balance prod
```

Requires `FLY_API_TOKEN` in the environment and membership in the `gunk-dev` Fly org.

## CI

A CI workflow runs on every pull request and push to main:

- **lint**: `nixfmt --check` and `nix flake check`
- **validate-cue**: validates CUE schemas and verifies export for all environments (flux and balance)
- **build**: builds the OCI image (flux)
- **zizmor**: security lints GitHub Actions workflows

### Flux deployments

Triggered from the [flux repo](https://github.com/patflynn/flux) via `repository_dispatch`:

- **Preview**: `flux-preview` event on PR open/sync — deploys a per-PR preview app, comments the URL on the PR
- **Preview cleanup**: `flux-preview-cleanup` event on PR close — destroys the preview app
- **Staging**: `flux-staging` event on merge to main — deploys to `flux-staging`
- **Production**: Manual `workflow_dispatch` in this repo

### Balance deployments

Triggered from the [balance repo](https://github.com/patflynn/balance) via `repository_dispatch`. The balance repo builds its own OCI image and passes the image reference in `client_payload.image`.

- **Preview**: `balance-preview` event on PR open/sync — deploys a per-PR preview app, comments the URL on the PR
- **Preview cleanup**: `balance-preview-cleanup` event on PR close — destroys the preview app
- **Staging**: `balance-staging` event on merge to main — deploys to `balance-staging`
- **Production**: Manual `workflow_dispatch` in this repo (requires `image` input)

### Secrets

Deploy workflows read `FLY_API_TOKEN` from GitHub **environments** (preview, staging, production), not repo-level secrets.

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

## Cleanup

```sh
# Destroy a preview app
./scripts/preview-cleanup.sh 42
```
