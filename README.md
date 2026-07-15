# cnpg-timescaledb

A CloudNativePG-compatible PostgreSQL operand image with the TimescaleDB
extension preinstalled. It builds on the official
[CloudNativePG](https://cloudnative-pg.io/) Postgres base, so it drops into a
CNPG `Cluster` without changes.

Pinned to PostgreSQL 18 and TimescaleDB 2.26.4 on Debian trixie.

## Why this image exists

CNPG's official extension catalog ships pgvector, PostGIS, and pgAudit, but not
TimescaleDB. Timescale's own `timescaledb-ha` image embeds Patroni, which
conflicts with the CNPG instance manager. This image adds TimescaleDB on top of
the upstream CNPG base and nothing else.

## Image

```text
ghcr.io/sedaprotocol/cnpg-timescaledb:<pg_major>-ts<timescale_version>
```

Each build produces three tags:

| Tag | Description |
| --- | --- |
| `18-ts2.26.4` | Rolling, latest bi-weekly rebuild |
| `18-ts2.26.4-<YYYYMMDD>` | Date-stamped, immutable |
| `18-ts2.26.4-<YYYYMMDD>-<git_sha>` | Fully pinned |

Use a date-stamped or fully-pinned tag in production.

## Usage in a CNPG `Cluster`

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: candle-tsdb
  namespace: timescale
spec:
  instances: 3
  imageName: ghcr.io/sedaprotocol/cnpg-timescaledb:18-ts2.26.4
  postgresql:
    parameters:
      shared_preload_libraries: "timescaledb"
      # CAGG-heavy schema: size the scheduler pool above the total policy count.
      timescaledb.max_background_workers: "32"
      max_worker_processes: "48"
  bootstrap:
    initdb:
      database: candle
      owner: admin
      postInitApplicationSQL:
        - "CREATE EXTENSION IF NOT EXISTS timescaledb;"
```

`shared_preload_libraries: timescaledb` is required. CNPG does not allow the
extension to load dynamically.

## Build

Builds run through GitHub Actions (`.github/workflows/build.yml`):

- Bi-weekly schedule, the 1st and 15th at 06:00 UTC
- On `main` pushes that touch the build
- On manual dispatch

Images are multi-arch (amd64 and arm64) with provenance and SBOM attestations.

Force a build with specific versions:

```bash
gh workflow run build.yml \
  -f pg_major=18 \
  -f timescale_version=2.26.4 \
  -f debian_release=trixie
```

Publishing uses the workflow's `GITHUB_TOKEN` (no extra registry secret needed);
the workflow requests `packages: write`.

## Version policy

- The CNPG base is pulled via the rolling `18-standard-trixie` tag, so each
  build picks up Postgres minor and CVE patches. PG major and Debian release
  stay pinned.
- TimescaleDB is pinned to `2.26.x`. Renovate PRs point releases and blocks
  `2.27+` to keep retention and continuous-aggregate behaviour validated.
- The base image's Debian codename must match the TimescaleDB `~debian<N>`
  package suffix. The Dockerfile asserts this and fails the build on a mismatch.
