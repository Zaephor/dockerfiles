#!/usr/bin/env bash
#
# OpenLDAP (slapd) entrypoint — minimal image.
#
# On first start (empty cn=config) it generates a minimal cn=config via slaptest:
# the standard schemas + the mdb module + a config database whose administrator is
# root over the ldapi socket (SASL/EXTERNAL). It creates NO data database and NO
# base suffix — all real configuration (suffix, rootDN/pw, TLS, overlays, data,
# syncrepl) is applied afterward over ldapi:/// by the orchestrator (Ansible).
#
# Persisted, mount these:
#   /etc/ldap/slapd.d  - the cn=config tree
#   /var/lib/ldap      - the mdb backend data
#
# Environment variables:
#   SLAPD_URLS       - listener URLs        (default: "ldap:/// ldaps:/// ldapi:///")
#   SLAPD_LOG_LEVEL  - slapd -d debug/log level, integer or keyword (default: 256 = stats)
#
set -euo pipefail

SLAPD_DIR="/etc/ldap/slapd.d"
DATA_DIR="/var/lib/ldap"
RUN_DIR="/run/slapd"
BOOTSTRAP_CONF="/usr/local/share/openldap/bootstrap.slapd.conf"
SLAPD_URLS="${SLAPD_URLS:-ldap:/// ldaps:/// ldapi:///}"
SLAPD_LOG_LEVEL="${SLAPD_LOG_LEVEL:-256}"

# Command pass-through: only bootstrap + launch the server when invoked as the
# slapd server (the default CMD). Any other command (`slapd -VV`, a debug shell,
# one-off tooling) runs as-is so the image stays generally usable.
if [[ "${1:-slapd}" != "slapd" ]]; then
    exec "$@"
fi
[[ $# -gt 0 ]] && shift   # drop the leading "slapd" token; keep any extra flags

mkdir -p "$RUN_DIR" "$SLAPD_DIR" "$DATA_DIR"
chown openldap:openldap "$RUN_DIR" "$DATA_DIR" 2>/dev/null || true

if [[ ! -e "$SLAPD_DIR/cn=config.ldif" ]]; then
    echo "[entrypoint] empty slapd.d — generating minimal cn=config from bootstrap.slapd.conf"
    slaptest -f "$BOOTSTRAP_CONF" -F "$SLAPD_DIR"
    chown -R openldap:openldap "$SLAPD_DIR"
fi

echo "[entrypoint] starting slapd (urls: ${SLAPD_URLS}, loglevel: ${SLAPD_LOG_LEVEL})"
# -d keeps slapd in the foreground (required in a container) and sends logs to
# stderr; the orchestrator can lower SLAPD_LOG_LEVEL or set olcLogLevel later.
exec slapd -h "$SLAPD_URLS" -u openldap -g openldap -F "$SLAPD_DIR" -d "$SLAPD_LOG_LEVEL" "$@"
