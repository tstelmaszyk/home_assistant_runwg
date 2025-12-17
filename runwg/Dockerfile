ARG BUILD_FROM
FROM $BUILD_FROM

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