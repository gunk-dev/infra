# infra

Fly.io infrastructure for [Flux](https://github.com/patflynn/flux), managed with CUE and Nix.

## Prerequisites

- [Nix](https://nixos.org/) with flakes enabled

## Dev shell

```sh
nix develop
```

Provides: `flyctl`, `cue`, `skopeo`

## Build OCI image locally

```sh
nix build .#oci-image
# Produces result -> a Docker archive tarball
```

The image contains Caddy serving the Flux static assets on port 8080.

## CUE config

All Fly.io configuration lives in CUE. `fly.toml` is never checked in — it's generated at deploy time.

```sh
# Validate all environments
cue vet ./apps/flux/...

# Export a specific environment
cue export ./apps/flux -t staging -e staging --out toml
```

### Environments

| Environment | App name | auto_stop | min_machines |
|---|---|---|---|
| preview | `flux-preview-{pr}` | suspend | 0 |
| staging | `flux-staging` | suspend | 1 |
| prod | `flux-prod` | off | 1 |

## Deploy

```sh
# Preview (requires PR number)
./scripts/deploy.sh preview 42

# Staging
./scripts/deploy.sh staging

# Production
./scripts/deploy.sh prod
```

Requires `FLY_API_TOKEN` in the environment and membership in the `gunk-dev` Fly org.

## CI

Deployments are triggered from the [flux repo](https://github.com/patflynn/flux) via `repository_dispatch`:

- **Preview**: `flux-preview` event on PR open/sync — deploys a per-PR preview app, comments the URL on the PR
- **Staging**: `flux-staging` event on merge to main — deploys to `flux-staging`
- **Production**: Manual `workflow_dispatch` in this repo

### Flux repo setup

The flux repo needs to send `repository_dispatch` events to this repo:

```yaml
# On PR events
- uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.INFRA_DISPATCH_TOKEN }}
    repository: gunk-dev/infra
    event-type: flux-preview
    client-payload: '{"pr_number": "${{ github.event.pull_request.number }}", "action": "${{ github.event.action }}"}'

# On merge to main
- uses: peter-evans/repository-dispatch@v3
  with:
    token: ${{ secrets.INFRA_DISPATCH_TOKEN }}
    repository: gunk-dev/infra
    event-type: flux-staging
```

Requires an `INFRA_DISPATCH_TOKEN` secret (PAT with `repo` scope on `gunk-dev/infra`).

## Cleanup

```sh
# Destroy a preview app
./scripts/preview-cleanup.sh 42
```
