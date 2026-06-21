# openldap

Minimal **OpenLDAP** (`slapd` 2.6.x) on `debian:trixie-slim`. The image ships only
the server + tooling; **all real configuration is applied at runtime over `ldapi://`**
by the orchestrator (the homelab `homelab.openldap` Ansible roles). This keeps the
image a near-static dependency and the configuration logic in version-controlled
Ansible — deliberately the opposite of an env-driven bootstrap image.

## What the image does

- Installs `slapd`, `ldap-utils`, `tini` and **wipes** the package's auto-created
  `cn=config` + sample data DB, leaving a blank slate.
- On **first start** (`entrypoint.sh`), generates a minimal `cn=config` via
  `slaptest` (see `bootstrap.slapd.conf`): standard schemas, the `mdb` module, and a
  config database whose only admin is **root over `ldapi` (SASL/EXTERNAL)**. No data
  database and no base suffix are created.
- Starts `slapd` in the foreground. The orchestrator then adds the suffix/rootDN/
  TLS/overlays/data/syncrepl over `ldapi:///` exactly as before.

## Tags

`ghcr.io/<owner>/<repo>/openldap` — `latest`, `{slapd-version}` (e.g. `2.6.10`),
`{commit}`. The version tracks Debian Trixie's `slapd` package.

## Runtime

| | |
|---|---|
| Ports | `389` (LDAP/StartTLS), `636` (LDAPS) |
| Persist (mount) | `/etc/ldap/slapd.d` (config), `/var/lib/ldap` (data) |
| Env | `SLAPD_URLS` (default `ldap:/// ldaps:/// ldapi:///`), `SLAPD_LOG_LEVEL` (default `256`) |
| Config | applied at runtime via `ldapmodify -Y EXTERNAL -H ldapi:///` |

TLS certs are provided by the orchestrator (mount them and point `olcTLSCertificateFile`
etc. via `ldapi`); the image bakes none.

## Local build + test

From the repo root:

```bash
dockerfiles/scripts/build-local.sh openldap   # build + smoke-test
dockerfiles/scripts/validate.sh openldap      # hadolint + yamllint + metadata + shellcheck
```

> This folder is maintained in the homelab monorepo and mirrored to the upstream
> public image repo (`github.com/Zaephor/dockerfiles`), whose CI builds + pushes it
> to ghcr.
