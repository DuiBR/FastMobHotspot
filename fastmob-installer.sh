#!/data/data/com.termux/files/usr/bin/bash
set -u

ROOT_DIR="/data/adb/fastmob-firewall"
ENGINE="$ROOT_DIR/fastmob-firewall.sh"
CONFIG="$ROOT_DIR/config.conf"
TERMUX_PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
TERMUX_BIN="$TERMUX_PREFIX/bin"
TMP_ENGINE="$HOME/.fastmob-firewall-engine.tmp"
TMP_CONFIG="$HOME/.fastmob-firewall-config.tmp"

say() { printf '%s\n' "$*"; }
die() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

command -v su >/dev/null 2>&1 || die "o comando su não foi encontrado. O aparelho precisa ter root."

say "Verificando acesso root..."
ROOT_UID="$(su -c 'id -u' 2>/dev/null | tr -d '\r\n')"
[ "$ROOT_UID" = "0" ] || die "acesso root não concedido. Autorize o Termux no Magisk e execute novamente."

cat > "$TMP_ENGINE" <<'ENGINE_SCRIPT'
#!/system/bin/sh

PATH=/system/bin:/system/xbin:/vendor/bin:/product/bin:/data/adb/magisk:$PATH

ROOT_DIR="/data/adb/fastmob-firewall"
CONFIG="$ROOT_DIR/config.conf"
STATE="$ROOT_DIR/state.conf"
CHAIN4="FASTMOB_ONLY"
CHAIN6="FASTMOB6_ONLY"

# IPs atuais dos servidores informados:
# vps1/vps3/vps4.fastmob.app.br -> 144.22.139.151
# vps2.fastmob.app.br           -> 163.176.118.248
DEFAULT_SERVER_IPS="144.22.139.151 163.176.118.248"

# DNS é liberado apenas para permitir que o aplicativo resolva os domínios
# dos servidores antes de o túnel VPN ser estabelecido.
DEFAULT_ALLOW_DNS="1"

say() { printf '%s\n' "$*"; }

require_root() {
    if [ "$(id -u)" != "0" ]; then
        say "ERRO: este comando precisa ser executado como root."
        exit 1
    fi
}

load_config() {
    HOTSPOT_IF=""
    SERVER_IPS="$DEFAULT_SERVER_IPS"
    ALLOW_DNS="$DEFAULT_ALLOW_DNS"

    if [ -f "$CONFIG" ]; then
        # Arquivo criado pelo próprio instalador, acessível apenas ao root.
        . "$CONFIG"
    fi
}

save_config() {
    TMP="$CONFIG.tmp"
    {
        printf 'HOTSPOT_IF=%s\n' "$HOTSPOT_IF"
        printf 'SERVER_IPS="%s"\n' "$SERVER_IPS"
        printf 'ALLOW_DNS=%s\n' "$ALLOW_DNS"
    } > "$TMP" || return 1
    chmod 600 "$TMP" 2>/dev/null
    mv -f "$TMP" "$CONFIG"
}

is_valid_iface() {
    case "$1" in
        ""|*[!a-zA-Z0-9_.:-]*) return 1 ;;
        *) return 0 ;;
    esac
}

detect_hotspot_interface() {
    # Método principal: estado oficial do serviço de tethering.
    IFACE="$(dumpsys tethering 2>/dev/null | sed -n 's/^[[:space:]]*\([^[:space:]]*\)[[:space:]]*- TetheredState.*/\1/p' | head -n 1)"

    if is_valid_iface "$IFACE" && ip link show "$IFACE" >/dev/null 2>&1; then
        printf '%s' "$IFACE"
        return 0
    fi

    # Alternativa: interface Wi-Fi/SoftAP ativa com IPv4 privado.
    IFACE="$(ip -o -4 addr show up 2>/dev/null | awk '
        $2 ~ /^(wlan[0-9]+|softap[0-9]+|ap_br_wlan[0-9]+|ap_br_softap[0-9]+|swlan[0-9]+|ap[0-9]+)$/ &&
        $4 ~ /^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)/ {
            print $2; exit
        }')"

    if is_valid_iface "$IFACE"; then
        printf '%s' "$IFACE"
        return 0
    fi

    return 1
}

detect_upstream_interface() {
    dumpsys tethering 2>/dev/null | sed -n 's/.*Current upstream interface(s): \[\([^],]*\).*/\1/p' | head -n 1
}

remove_jump4() {
    while :; do
        NUM="$(iptables -w -L FORWARD -n --line-numbers 2>/dev/null | awk -v c="$CHAIN4" '$2 == c {print $1; exit}')"
        [ -n "$NUM" ] || break
        iptables -w -D FORWARD "$NUM" 2>/dev/null || break
    done
}

remove_jump6() {
    command -v ip6tables >/dev/null 2>&1 || return 0
    while :; do
        NUM="$(ip6tables -w -L FORWARD -n --line-numbers 2>/dev/null | awk -v c="$CHAIN6" '$2 == c {print $1; exit}')"
        [ -n "$NUM" ] || break
        ip6tables -w -D FORWARD "$NUM" 2>/dev/null || break
    done
}

remove_ipv4_rules() {
    remove_jump4
    iptables -w -F "$CHAIN4" 2>/dev/null
    iptables -w -X "$CHAIN4" 2>/dev/null
}

remove_ipv6_rules() {
    command -v ip6tables >/dev/null 2>&1 || return 0
    remove_jump6
    ip6tables -w -F "$CHAIN6" 2>/dev/null
    ip6tables -w -X "$CHAIN6" 2>/dev/null
}

firewall_on() {
    load_config

    # Sempre reaplica a configuração necessária do tethering.
    settings put global tether_offload_disabled 1 >/dev/null 2>&1

    DETECTED="$(detect_hotspot_interface 2>/dev/null)"
    if [ -n "$DETECTED" ]; then
        HOTSPOT_IF="$DETECTED"
        save_config >/dev/null 2>&1
    fi

    if ! is_valid_iface "$HOTSPOT_IF" || ! ip link show "$HOTSPOT_IF" >/dev/null 2>&1; then
        say "ERRO: não foi possível detectar a interface do hotspot."
        say "Ligue o hotspot e execute: fastmob-detect"
        exit 1
    fi

    remove_ipv4_rules
    remove_ipv6_rules

    iptables -w -N "$CHAIN4" 2>/dev/null || true
    iptables -w -F "$CHAIN4" || exit 1

    # DNS de bootstrap. Não libera navegação, apenas consultas DNS.
    if [ "$ALLOW_DNS" = "1" ]; then
        iptables -w -A "$CHAIN4" -p udp --dport 53 -j ACCEPT
        iptables -w -A "$CHAIN4" -p tcp --dport 53 -j ACCEPT
    fi

    # Permite somente os IPs dos servidores FASTMOB.
    for IP in $SERVER_IPS; do
        iptables -w -A "$CHAIN4" -d "$IP" -j ACCEPT
    done

    # Bloqueia todo o restante do tráfego IPv4 encaminhado pelo hotspot.
    iptables -w -A "$CHAIN4" -j DROP
    iptables -w -I FORWARD 1 -i "$HOTSPOT_IF" -j "$CHAIN4" || exit 1

    # Impede bypass por IPv6.
    if command -v ip6tables >/dev/null 2>&1; then
        ip6tables -w -N "$CHAIN6" 2>/dev/null || true
        ip6tables -w -F "$CHAIN6"
        ip6tables -w -A "$CHAIN6" -j DROP
        ip6tables -w -I FORWARD 1 -i "$HOTSPOT_IF" -j "$CHAIN6"
    fi

    {
        printf 'ACTIVE=1\n'
        printf 'ACTIVE_IF=%s\n' "$HOTSPOT_IF"
    } > "$STATE"
    chmod 600 "$STATE" 2>/dev/null

    say ""
    say "======================================"
    say " FIREWALL FASTMOB ATIVADO"
    say "======================================"
    say "Hotspot: $HOTSPOT_IF"
    UPSTREAM="$(detect_upstream_interface)"
    [ -n "$UPSTREAM" ] && say "Internet móvel: $UPSTREAM"
    say "DNS de bootstrap: $([ "$ALLOW_DNS" = "1" ] && echo LIBERADO || echo BLOQUEADO)"
    say "Servidores permitidos: $SERVER_IPS"
    say "IPv6: BLOQUEADO"
    say ""
    say "Sem a VPN, os clientes não terão navegação normal."
}

firewall_off() {
    load_config
    remove_ipv4_rules
    remove_ipv6_rules
    rm -f "$STATE"

    say ""
    say "======================================"
    say " FIREWALL FASTMOB DESATIVADO"
    say "======================================"
    say "O hotspot voltou a compartilhar a Internet normalmente."
}

firewall_status() {
    load_config

    ACTIVE="0"
    if iptables -w -L FORWARD -n 2>/dev/null | awk -v c="$CHAIN4" '$1 == c {found=1} END {exit !found}'; then
        ACTIVE="1"
    fi

    say ""
    say "======================================"
    say " STATUS DO FIREWALL FASTMOB"
    say "======================================"
    say "Interface configurada: ${HOTSPOT_IF:-não detectada}"
    CURRENT="$(detect_hotspot_interface 2>/dev/null)"
    say "Interface atual: ${CURRENT:-hotspot desligado/não detectado}"
    say "Offload desativado: $(settings get global tether_offload_disabled 2>/dev/null)"
    say "Servidores permitidos: $SERVER_IPS"
    say "DNS de bootstrap: $([ "$ALLOW_DNS" = "1" ] && echo LIBERADO || echo BLOQUEADO)"

    if [ "$ACTIVE" = "1" ]; then
        say "Status: ATIVADO"
        say ""
        iptables -w -L "$CHAIN4" -n -v --line-numbers 2>/dev/null
        if command -v ip6tables >/dev/null 2>&1; then
            say ""
            say "IPv6: BLOQUEADO"
        fi
    else
        say "Status: DESATIVADO"
    fi
}

firewall_detect() {
    load_config
    DETECTED="$(detect_hotspot_interface 2>/dev/null)"
    UPSTREAM="$(detect_upstream_interface)"

    say ""
    say "======================================"
    say " DETECÇÃO FASTMOB"
    say "======================================"

    if [ -n "$DETECTED" ]; then
        HOTSPOT_IF="$DETECTED"
        save_config
        ADDRESS="$(ip -o -4 addr show dev "$DETECTED" 2>/dev/null | awk '{print $4; exit}')"
        say "Hotspot detectado: $DETECTED"
        [ -n "$ADDRESS" ] && say "Rede do hotspot: $ADDRESS"
        [ -n "$UPSTREAM" ] && say "Internet móvel: $UPSTREAM"
        say "Configuração salva automaticamente."
    else
        say "Hotspot não detectado."
        say "Ligue o hotspot e execute fastmob-detect novamente."
    fi

    say ""
    say "Interfaces ativas:"
    ip -br addr 2>/dev/null | awk '$2 != "DOWN" {print}'
}

require_root
mkdir -p "$ROOT_DIR" 2>/dev/null

case "${1:-}" in
    on) firewall_on ;;
    off) firewall_off ;;
    status) firewall_status ;;
    detect) firewall_detect ;;
    *)
        say "Uso: fastmob-on | fastmob-off | fastmob-status | fastmob-detect"
        exit 1
        ;;
esac
ENGINE_SCRIPT

cat > "$TMP_CONFIG" <<'CONFIG_FILE'
HOTSPOT_IF=
SERVER_IPS="144.22.139.151 163.176.118.248"
ALLOW_DNS=1
CONFIG_FILE

say "Instalando o mecanismo do firewall..."
su -c "mkdir -p '$ROOT_DIR' && cp '$TMP_ENGINE' '$ENGINE' && chmod 700 '$ENGINE'"

# Não sobrescreve a configuração existente em reinstalações.
su -c "if [ ! -f '$CONFIG' ]; then cp '$TMP_CONFIG' '$CONFIG'; chmod 600 '$CONFIG'; fi"

rm -f "$TMP_ENGINE" "$TMP_CONFIG"

mkdir -p "$TERMUX_BIN" || die "não foi possível acessar $TERMUX_BIN"

create_wrapper() {
    NAME="$1"
    ACTION="$2"
    FILE="$TERMUX_BIN/$NAME"
    cat > "$FILE" <<WRAPPER
#!$TERMUX_PREFIX/bin/sh
exec su -c "$ENGINE $ACTION"
WRAPPER
    chmod 700 "$FILE"
}

create_wrapper fastmob-on on
create_wrapper fastmob-off off
create_wrapper fastmob-status status
create_wrapper fastmob-detect detect

say "Desativando o offload do tethering..."
su -c 'settings put global tether_offload_disabled 1' >/dev/null 2>&1

say "Tentando detectar o hotspot..."
DETECT_OUTPUT="$(su -c "$ENGINE detect" 2>&1)"
printf '%s\n' "$DETECT_OUTPUT"

say ""
say "======================================"
say " INSTALAÇÃO CONCLUÍDA"
say "======================================"
say "Comandos instalados:"
say "  fastmob-on"
say "  fastmob-off"
say "  fastmob-status"
say "  fastmob-detect"
say ""
say "Uso diário:"
say "  1. Ligue o hotspot"
say "  2. Execute fastmob-on"
say "  3. Para liberar novamente, execute fastmob-off"
say ""
say "Caso o shell ainda não encontre os comandos, feche e abra o Termux."
