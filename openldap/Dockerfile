# syntax=docker/dockerfile:1
FROM debian:trixie-slim

# Minimal OpenLDAP (slapd 2.6.x from Debian Trixie). Package versions are
# intentionally unpinned — the image is rebuilt to track the distro package
# (see metadata.yaml version_source: binary_version).
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        slapd \
        ldap-utils \
        tini \
    && rm -rf /var/lib/apt/lists/* \
    # Blank slate: the slapd postinst auto-creates a cn=config AND a sample data
    # DB (with a hostname-derived suffix). Remove both so the entrypoint generates
    # a clean minimal cn=config and ALL real configuration (suffix, rootDN, TLS,
    # overlays, data, syncrepl) is applied afterward over ldapi by the orchestrator.
    && rm -rf /etc/ldap/slapd.d/* /var/lib/ldap/*

COPY bootstrap.slapd.conf /usr/local/share/openldap/bootstrap.slapd.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# 389 = LDAP + StartTLS, 636 = LDAPS. Stateful paths (mount these): the cn=config
# tree /etc/ldap/slapd.d and the mdb data /var/lib/ldap.
EXPOSE 389 636

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["slapd"]
