# Repository context

## Purpose
Fly.io infrastructure-as-code for three apps consumed by their respective product repos: Flux (`patflynn/flux`), Balance (`patflynn/balance`), and Web/gunk.dev (`gunk-dev/gunk-web`). Fly app configuration is authored in CUE and exported to `fly.toml` at deploy time; DNS records for `gunk.dev` are also authored in CUE and synced to Porkbun. Deployments are driven by `repository_dispatch` events from the product repos and delegate to reusable workflows in `gunk-dev/armstrong`.

## Tech stack
- Nix flake (`flake.nix`) with `nixpkgs-unstable`; flake inputs include `flux`, `gunk-web`, and `balance` repos (`flake.nix:5-10`).
- CUE for config; module is `gunk.dev/infra` at language version `v0.9.2` (`cue.mod/module.cue`).
- Dev-shell tools: `flyctl`, `cue`, `jq`, `skopeo`, `nixfmt` (`flake.nix:93-101`).
- OCI images built via `pkgs.dockerTools.buildLayeredImage` using `caddy` (`flake.nix:31-83`).
- GitHub Actions for CI and deployment (`.github/workflows/`).

## Entry points
- `flake.nix` — Nix flake; exposes packages `default`/`oci-image` (Flux), `web-oci-image` (gunk-web), `balance-oci-image` (re-exports image built in the balance flake), and `devShells.default`.
- `apps/{flux,balance,web}/base.cue` — base `#FlyApp` definitions, composed with per-environment files (`preview.cue`, `staging.cue`, `prod.cue`), gated by CUE `@if(<env>)` tags.
- `apps/flux/Caddyfile` — Caddy config baked into the Flux OCI image (serves `/srv/www` with SPA fallback on `:8080`).
- `dns/gunk.dev.cue` — declarative DNS records for `gunk.dev`.
- `cue.mod/pkg/gunk.dev/armstrong/schema/{fly.cue,dns.cue}` — vendored schemas (`#FlyApp`, `#HttpService`, `#HttpCheck`, `#DNSRecord`) used by app and DNS configs.

## Layout
- `apps/` — per-app CUE configs (`flux/`, `balance/`, `web/`), each containing `base.cue` plus `preview.cue`, `staging.cue`, `prod.cue`. `apps/flux/` additionally holds `Caddyfile`.
- `dns/` — CUE definitions of DNS records for `gunk.dev` (`gunk.dev.cue`).
- `cue.mod/` — CUE module root; `pkg/gunk.dev/armstrong/schema/` vendors `#FlyApp` and `#DNSRecord` schemas.
- `.github/workflows/` — CI (`ci.yml`), DNS sync (`dns.yml`), and per-app `preview`/`staging`/`prod`/`update` workflows for flux, balance, and web.
- `.github/dependabot.yml` — Dependabot config.
- `flake.nix` / `flake.lock` — Nix flake definition and pinned inputs.

## Build, test, run
Enter the dev shell first (provides `cue`, `flyctl`, `jq`, `skopeo`, `nixfmt`):
```sh
nix develop
```

Validate and export CUE configs (commands taken from `README.md` and `.github/workflows/ci.yml`):
```sh
# Validate per app
cue vet ./apps/flux/...
cue vet ./apps/balance/...
cue vet ./apps/web/...

# Validate specific environment (matches CI)
cue vet ./apps/flux -t staging
cue vet ./apps/flux -t prod
cue vet ./apps/flux -t preview

# Export an environment to fly.toml
cue export ./apps/flux    -t staging -e staging --out toml
cue export ./apps/balance -t staging -e staging --out toml
cue export ./apps/web     -t staging -e staging --out toml

# Preview exports take an additional appName tag
cue export ./apps/flux    -t preview -t appName=flux-preview-42      -e preview --out toml
cue export ./apps/balance -t preview -t appName=balance-preview-42   -e preview --out toml
cue export ./apps/web     -t preview -t appName=gunk-web-preview-42  -e preview --out toml

# DNS
cue vet ./dns
cue export ./dns --out json
```

Build OCI images locally:
```sh
nix build .#oci-image          # Flux (default)
nix build .#web-oci-image      # gunk-web
nix build .#balance-oci-image  # Balance (sourced from balance flake input)
```

CI / lint commands (from `.github/workflows/ci.yml`):
```sh
nix develop -c nixfmt --check .
nix flake check
nix run nixpkgs#zizmor -- . --no-online-audits
```

No project-level test suite exists; CI's smoke test loads the built OCI image with `docker load`, runs it on port 8080, and `curl -f http://localhost:8080/` (`.github/workflows/ci.yml:103-110`).

## Conventions
- `fly.toml` is never committed — it is generated at deploy time and is gitignored (`README.md:64`, `.gitignore`).
- App configs build on `_base: schema.#FlyApp` from `apps/<app>/base.cue`; environment files (`preview.cue`/`staging.cue`/`prod.cue`) start with `@if(<env>)` and define a single top-level value of the same name (e.g. `preview: _base & { ... }`). Export uses matching `-e <env>` and `-t <env>` flags.
- Preview app names use the `@tag(appName)` mechanism in CUE (`apps/flux/preview.cue:5`), so callers must pass `-t appName=<name>` for preview exports.
- All Fly apps listen on internal port `8080` (`apps/flux/base.cue`, `cue.mod/pkg/gunk.dev/armstrong/schema/fly.cue`, `apps/flux/Caddyfile`).
- DNS records are added by appending an entry to the `records:` list in `dns/gunk.dev.cue`, conforming to `schema.#DNSRecord` from `cue.mod/pkg/gunk.dev/armstrong/schema/dns.cue`.
- Deploy/CI workflows pin actions by full commit SHA with version comments (e.g. `actions/checkout@de0fac2e...# v4` in `.github/workflows/ci.yml`).
- Workflow jobs use `permissions: contents: read` at the top of `ci.yml` and explicit `persist-credentials: false` on checkout.

## Gotchas
- `apex` of `gunk.dev` uses `A`/`AAAA` records, not a CNAME, because CNAMEs are not allowed on a zone apex (`dns/gunk.dev.cue:28-30`).
- The Balance OCI image is **not** built in this repo — it comes from the `balance` flake input (`flake.nix:27`) for local builds and from `client_payload.image` for deploys (`README.md:27,132`).
- Preview cleanup must succeed for `*-preview-cleanup` events to remove the corresponding preview app and preview CNAME record (`README.md:53,126,135,144`).
- Deploys rely on GitHub environments (`preview`, `staging`, `prod`, `dns`, `automation`) for secrets — not repo-level secrets (`README.md:148-154`).

## External dependencies
- **Fly.io** — runtime for all three apps; deploys via `flyctl` using `FLY_API_TOKEN` from per-environment GitHub secrets.
- **Porkbun** — DNS provider for `gunk.dev`; synced via armstrong's DNS workflow using `PORKBUN_API_KEY` / `PORKBUN_SECRET_KEY`.
- **gunk-dev/armstrong** — provides reusable deploy/DNS workflows and the vendored CUE schemas under `cue.mod/pkg/gunk.dev/armstrong/`.
- **Product repos**: `patflynn/flux`, `patflynn/balance`, `gunk-dev/gunk-web` — emit `repository_dispatch` events into this repo and (for balance/web) supply pre-built OCI image references.
- **Fastmail** — receives mail for `gunk.dev` via MX + DKIM records declared in `dns/gunk.dev.cue`.
- **GitHub App** — used for cross-repo PR comments and auto-merge on flake.lock update PRs; `APP_ID` / `APP_PRIVATE_KEY` stored in `preview` and `automation` environments (`README.md:152`).
