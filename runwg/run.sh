#!/bin/bash
set -e

echo "=== Démarrage WireGuard Custom (mode host) ==="

# Parser la config
CONFIG_FILE="/data/options.json"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERREUR: $CONFIG_FILE introuvable"
    exit 1
fi

echo "Lecture de la configuration..."
PRIVATE_KEY=$(jq -r '.interface.private_key' "$CONFIG_FILE")
ADDRESS=$(jq -r '.interface.address' "$CONFIG_FILE")
PUBLIC_KEY=$(jq -r '.peer.public_key' "$CONFIG_FILE")
PSK=$(jq -r '.peer.preshared_key' "$CONFIG_FILE")
ENDPOINT=$(jq -r '.peer.endpoint' "$CONFIG_FILE")
ALLOWED_IPS=$(jq -r '.peer.allowed_ips // "0.0.0.0/0, ::0/0"' "$CONFIG_FILE")

echo "Configuration chargée"

# Extraire les adresses
IPV4=$(echo "$ADDRESS" | cut -d',' -f1 | tr -d ' ')
IPV6=$(echo "$ADDRESS" | cut -d',' -f2 | tr -d ' ')

echo "IPv4: $IPV4"
[ -n "$IPV6" ] && [ "$IPV6" != "$IPV4" ] && echo "IPv6: $IPV6"

# Nettoyer si existant
ip link delete dev wg0 2>/dev/null || true

# Créer l'interface
echo "Création de l'interface wg0..."
ip link add dev wg0 type wireguard || {
    echo "✗ Impossible de créer wg0"
    echo "Vérifier que le mode host_network est actif"
    exit 1
}

# Configurer WireGuard
echo "Configuration de WireGuard..."
wg set wg0 private-key <(echo "$PRIVATE_KEY") \
    listen-port 0 \
    peer "$PUBLIC_KEY" \
    preshared-key <(echo "$PSK") \
    endpoint "$ENDPOINT" \
    allowed-ips "$ALLOWED_IPS" \
    persistent-keepalive 25

# Ajouter les adresses
echo "Attribution des adresses..."
ip addr add "$IPV4" dev wg0

if [ -n "$IPV6" ] && [ "$IPV6" != "$IPV4" ]; then
    echo "Attribution IPv6..."
    ip addr add "$IPV6" dev wg0
fi

# Activer l'interface
echo "Configuration MTU et activation..."
ip link set mtu 1420 dev wg0
ip link set wg0 up

# Routes (seulement si 0.0.0.0/0)
if echo "$ALLOWED_IPS" | grep -q "0.0.0.0/0"; then
    echo "Configuration du routage complet via VPN..."
    
    # Route l'endpoint par la gateway normale
    ENDPOINT_IP=$(echo "$ENDPOINT" | cut -d':' -f1)
    
    # Résoudre si c'est un hostname
    if ! echo "$ENDPOINT_IP" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
        echo "Résolution de $ENDPOINT_IP..."
        ENDPOINT_IP=$(nslookup "$ENDPOINT_IP" | grep "Address" | tail -1 | awk '{print $2}')
        echo "Résolu: $ENDPOINT_IP"
    fi
    
    # Obtenir la gateway par défaut
    GW=$(ip route | grep default | awk '{print $3}' | head -n1)
    DEV=$(ip route | grep default | awk '{print $5}' | head -n1)
    
    if [ -n "$GW" ] && [ -n "$ENDPOINT_IP" ]; then
        echo "Route $ENDPOINT_IP via $GW dev $DEV"
        ip route add "$ENDPOINT_IP" via "$GW" dev "$DEV" 2>/dev/null || echo "Route endpoint déjà existante"
    fi
    
    # Route par défaut via VPN
    echo "Ajout route par défaut via wg0..."
    ip route add default dev wg0 metric 100 2>/dev/null || echo "Route par défaut déjà configurée"
else
    echo "Routage split-tunnel (pas de route par défaut)"
fi

echo ""
echo "✓ WireGuard configuré"
echo ""
echo "=== État de l'interface ==="
ip addr show wg0

echo ""
echo "=== Configuration WireGuard ==="
wg show wg0

echo ""
echo "=== Routes ==="
ip route | grep wg0 || echo "Aucune route wg0"

echo ""
echo "=== Test de connectivité (attente 5s pour handshake) ==="
sleep 5

# Vérifier le handshake
echo "Handshake:"
wg show wg0 latest-handshakes

# Test ping
echo ""
echo "Ping vers le serveur VPN..."
if ping -c 3 -W 5 10.0.0.1; then
    echo "✓ Connexion au serveur VPN réussie!"
else
    echo "⚠ Pas de réponse du serveur VPN"
    echo ""
    echo "Vérifications à faire:"
    echo "  1. Sur le serveur: sudo wg show"
    echo "  2. Vérifier que le port UDP du serveur est ouvert"
    echo "  3. Tester: nslookup $ENDPOINT"
fi

echo ""
echo "=== VPN actif - Monitoring ==="

# Boucle de monitoring pour garder le conteneur actif
while sleep 30; do
    # Vérifier que l'interface existe toujours
    if ! ip link show wg0 > /dev/null 2>&1; then
        echo "✗ Interface wg0 disparue - Arrêt du conteneur"
        exit 1
    fi
    
    # Vérifier le handshake (warning si ancien)
    HANDSHAKE=$(wg show wg0 latest-handshakes 2>/dev/null | awk '{print $2}')
    if [ -n "$HANDSHAKE" ] && [ "$HANDSHAKE" != "0" ]; then
        AGE=$(($(date +%s) - HANDSHAKE))
        if [ $AGE -gt 180 ]; then
            echo "⚠ Pas de handshake récent (${AGE}s)"
        fi
    fi
    
    # Log toutes les 5 minutes (10 cycles de 30s)
    COUNTER=$((COUNTER + 1))
    if [ $((COUNTER % 10)) -eq 0 ]; then
        echo "✓ VPN actif - $(date)"
    fi
done