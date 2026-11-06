# Image de base multi-arch (amd64/aarch64). Depuis Supervisor 2026.04,
# BUILD_FROM n'est plus fourni : l'image doit être déclarée explicitement.
FROM ghcr.io/home-assistant/base:3.24

# Installer WireGuard et outils
RUN apk add --no-cache \
    wireguard-tools \
    iptables \
    ip6tables \
    bash

# Copier le script de démarrage
COPY run.sh /
RUN chmod a+x /run.sh

CMD ["/run.sh"]