#!/usr/bin/env bash
# Copyright 2025-2026 Dimensional Inc.
# Licensed under the Apache License, Version 2.0
#
# Fresh Unitree G1 to running DimOS, in one command. Start it, then plug in the ethernet cable.
#
# Usage:
#   ./g1-bringup.sh --ssid dimensional --psk-file ~/.g1-wifi
#   ./g1-bringup.sh --ssid dimensional --dry-run
#
# Stops before anything that moves the robot. Standing the G1 up is a human step; this prints
# the command and exits.
#
set -euo pipefail

trap 'printf "\n"; exit 130' INT

# ─── defaults ─────────────────────────────────────────────────────────────────
JETSON_IP="192.168.123.164"          # fixed by Unitree; the app's IP is the control computer
LAPTOP_IP="192.168.123.100/24"       # free address on the robot's internal subnet
ROBOT_USER="${G1_USER:-unitree}"
ROBOT_PASS="${G1_PASS:-123}"         # Unitree factory default
WIRED_PROFILE="g1-wired"
SSID="${G1_SSID:-}"
PSK="${G1_PSK:-}"
PSK_FILE=""
IFACE=""
DRY_RUN=0
CARRIER_TIMEOUT=300                  # seconds to wait for the cable
SSH_TIMEOUT=60
RECORD_DIR="${G1_RECORD_DIR:-$HOME/.dimos/fleet}"
ROBOT_HOST="$JETSON_IP"              # retargeted to the wifi address once step 2 lands
ROBOT_MODEL="unknown"
WIFI_IP=""
TAILSCALE=1                          # the wifi lease moves; a tailnet address does not
TS_AUTHKEY="${TS_AUTHKEY:-}"
TS_IP=""
TS_HOST=""
TS_LOGIN_URL=""

if [[ -t 1 ]] && command -v tput &>/dev/null && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; then
    CYAN=$'\033[38;5;44m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'
    BOLD=$'\033[1m'; DIMC=$'\033[2m'; RESET=$'\033[0m'
else
    CYAN="" GREEN="" YELLOW="" RED="" BOLD="" DIMC="" RESET=""
fi

info()  { printf "%s▸%s %s\n" "$CYAN" "$RESET" "$*"; }
ok()    { printf "%s✓%s %s\n" "$GREEN" "$RESET" "$*"; }
warn()  { printf "%s⚠%s %s\n" "$YELLOW" "$RESET" "$*" >&2; }
err()   { printf "%s✗%s %s\n" "$RED" "$RESET" "$*" >&2; }
die()   { err "$@"; exit 1; }
dimt()  { printf "%s%s%s\n" "$DIMC" "$*" "$RESET"; }
has_cmd() { command -v "$1" &>/dev/null; }

# Secrets are masked at the printing layer, so no call site can forget. 8 chars is the WPA2
# minimum, which also keeps a short literal from being chewed out of an IP or path.
mask() {
    local m="$1"
    if [[ ${#PSK} -ge 8 ]]; then m="${m//$PSK/********}"; fi
    if [[ ${#TS_AUTHKEY} -ge 8 ]]; then m="${m//$TS_AUTHKEY/tskey-********}"; fi
    printf '%s' "$m"
}

# All narration goes to stderr: callers capture rsh's stdout, and a >/dev/null cannot hide it.
trace()    { printf "%s[dry-run] %s%s\n" "$DIMC" "$(mask "$*")" "$RESET" >&2; }
say_cmd()  { printf "%s    $ %s%s\n" "$DIMC" "$(mask "$*")" "$RESET" >&2; }
phase()    { printf "\n%s── %s %s%s\n" "$BOLD" "$*" "──────────────────────────────" "$RESET" >&2; }

say_out() {
    if [[ -z "$1" ]]; then return 0; fi
    while IFS= read -r line; do
        printf "%s    │ %s%s\n" "$DIMC" "$(mask "$line")" "$RESET" >&2
    done <<< "$1"
}

run_cmd() {
    if [[ "$DRY_RUN" == "1" ]]; then trace "$*"; return 0; fi
    say_cmd "$*"
    eval "$@"
}

usage() {
    cat <<EOF
Bring a fresh Unitree G1 from the box to running DimOS.

Usage: g1-bringup.sh [OPTIONS]

With no options it puts the robot on the same network as this machine, reading the
ssid and password from this machine's own saved wifi profile.

Options:
  --ssid NAME        WiFi network for the robot to join (default: this machine's)
  --psk SECRET       WiFi password (default: this machine's saved secret)
  --psk-file PATH    read the WiFi password from a file, never the process list
  --iface NAME       wired interface (default: auto-detect)
  --user NAME        robot login (default: unitree)
  --pass SECRET      robot password (default: 123 — the factory default; units vary)
  --record-dir DIR   where the device record is written (default: ~/.dimos/fleet)
  --ts-authkey KEY   tailscale auth key (or \$TS_AUTHKEY) — without it, one manual approval
  --no-tailscale     skip tailscale entirely
  --dry-run          print every command, change nothing
  -h, --help         this

The robot never moves. Standing it up is printed, not run.
EOF
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ssid)       SSID="$2"; shift 2 ;;
            --psk)        PSK="$2"; shift 2 ;;
            --psk-file)   PSK_FILE="$2"; shift 2 ;;
            --iface)      IFACE="$2"; shift 2 ;;
            --user)       ROBOT_USER="$2"; shift 2 ;;
            --pass)       ROBOT_PASS="$2"; shift 2 ;;
            --record-dir) RECORD_DIR="$2"; shift 2 ;;
            --ts-authkey) TS_AUTHKEY="$2"; shift 2 ;;
            --no-tailscale) TAILSCALE=0; shift ;;
            --dry-run)    DRY_RUN=1; shift ;;
            -h|--help)    usage ;;
            *)            die "unknown option: $1 (try --help)" ;;
        esac
    done
    if [[ -n "$PSK_FILE" ]]; then PSK="$(< "$PSK_FILE")"; fi
}

# This laptop is already on the network the robot needs, so reuse its saved profile
# instead of retyping the secret. nmcli serves the psk to the owning user without root.
resolve_wifi() {
    local profile
    profile=$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null \
              | awk -F: '$2=="802-11-wireless"{print $1; exit}')
    if [[ -z "$SSID" ]]; then
        if [[ -z "$profile" ]]; then die "this machine is not on wifi — pass --ssid"; fi
        SSID=$(nmcli -g 802-11-wireless.ssid connection show "$profile" 2>/dev/null)
        if [[ -z "$SSID" ]]; then die "could not read the ssid of '$profile' — pass --ssid"; fi
        ok "ssid from this machine: $SSID"
    fi
    if [[ -z "$PSK" ]]; then
        PSK=$(nmcli -s -g 802-11-wireless-security.psk connection show "${profile:-$SSID}" 2>/dev/null)
        if [[ -z "$PSK" ]]; then
            die "no saved password for '$SSID' on this machine — pass --psk-file"
        fi
        ok "wifi password read from this machine's saved profile"
    fi
}

# ─── preflight ────────────────────────────────────────────────────────────────
check_prereqs() {
    has_cmd nmcli || die "nmcli not found — this script needs NetworkManager"
    has_cmd ssh   || die "ssh not found"
    [[ -f "$HOME/.ssh/id_ed25519.pub" || -f "$HOME/.ssh/id_rsa.pub" ]] \
        || die "no ssh public key — run: ssh-keygen -t ed25519"
}

# Pick the first wired interface that is not a bridge, docker, or virtual device.
detect_iface() {
    [[ -n "$IFACE" ]] && { ok "wired interface: $IFACE (given)"; return; }
    IFACE=$(nmcli -t -f DEVICE,TYPE device status 2>/dev/null \
            | awk -F: '$2=="ethernet"{print $1; exit}')
    [[ -z "$IFACE" ]] && die "no ethernet interface found — pass --iface"
    ok "wired interface: $IFACE"
}

# ─── step 1: wired link ───────────────────────────────────────────────────────
wait_for_carrier() {
    [[ "$DRY_RUN" == "1" ]] && { dimt "[dry-run] wait for carrier on $IFACE"; return 0; }
    if [[ "$(cat /sys/class/net/$IFACE/carrier 2>/dev/null || echo 0)" == "1" ]]; then
        ok "cable already connected"; return
    fi
    info "${BOLD}plug the robot's ethernet cable into this machine${RESET} (waiting ${CARRIER_TIMEOUT}s)"
    local waited=0
    while [[ $waited -lt $CARRIER_TIMEOUT ]]; do
        [[ "$(cat /sys/class/net/$IFACE/carrier 2>/dev/null || echo 0)" == "1" ]] \
            && { ok "cable detected"; sleep 2; return; }
        sleep 1; waited=$((waited + 1))
    done
    die "no cable after ${CARRIER_TIMEOUT}s on $IFACE"
}

ensure_wired_profile() {
    if nmcli -t -f NAME connection show 2>/dev/null | grep -qx "$WIRED_PROFILE"; then
        info "reusing $WIRED_PROFILE profile"
    else
        run_cmd "sudo nmcli connection add type ethernet ifname '$IFACE' con-name '$WIRED_PROFILE' \
                 ipv4.method manual ipv4.addresses '$LAPTOP_IP'"
    fi
    run_cmd "sudo nmcli connection up '$WIRED_PROFILE'"
    ok "laptop is ${LAPTOP_IP%/*} on the robot's subnet"
}

wait_for_jetson() {
    [[ "$DRY_RUN" == "1" ]] && { dimt "[dry-run] ping $JETSON_IP"; return 0; }
    local waited=0
    while [[ $waited -lt 60 ]]; do
        ping -c1 -W1 "$JETSON_IP" &>/dev/null && { ok "jetson answers at $JETSON_IP"; return; }
        sleep 2; waited=$((waited + 2))
    done
    die "no reply from $JETSON_IP after 60s — the G1 has two ethernet jacks; try the other one"
}

# ─── ssh plumbing ─────────────────────────────────────────────────────────────
# LogLevel=ERROR drops the per-call known-hosts warning that /dev/null guarantees on every connect.
SSH_OPTS=(-T -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR -o ConnectTimeout=8)

# stderr is shown but never merged into stdout — callers parse stdout for values.
rsh() {
    [[ "$DRY_RUN" == "1" ]] && { trace "ssh $ROBOT_USER@$ROBOT_HOST '$*'"; return 0; }
    local out rc errf
    errf=$(mktemp)
    say_cmd "ssh $ROBOT_USER@$ROBOT_HOST -- $*"
    out=$(timeout "$SSH_TIMEOUT" ssh "${SSH_OPTS[@]}" "$ROBOT_USER@$ROBOT_HOST" "$@" 2>"$errf"); rc=$?
    say_out "$out"; say_out "$(<"$errf")"; rm -f "$errf"
    printf '%s' "$out"
    return $rc
}

# Multi-line remote scripts ride stdin so nothing has to survive three levels of quoting.
rsh_script() {
    [[ "$DRY_RUN" == "1" ]] && { trace "ssh $ROBOT_USER@$ROBOT_HOST bash -l -s  <<script"; cat >/dev/null; return 0; }
    local script out rc errf
    errf=$(mktemp)
    script=$(cat)
    say_cmd "ssh $ROBOT_USER@$ROBOT_HOST -- bash -l -s  <<script"
    out=$(printf '%s' "$script" | timeout "$SSH_TIMEOUT" ssh "${SSH_OPTS[@]}" \
          "$ROBOT_USER@$ROBOT_HOST" "bash -l -s" 2>"$errf"); rc=$?
    say_out "$out"; say_out "$(<"$errf")"; rm -f "$errf"
    return $rc
}

# Robot-side sudo reads the factory password from stdin so no TTY is needed.
rsudo() { rsh "echo '$ROBOT_PASS' | sudo -S -p '' $*"; }

# The server offers the same error for a bad password and an unknown user, so name both.
key_access_failed() {
    local methods
    methods=$(ssh -v -o BatchMode=yes -o ConnectTimeout=8 "$ROBOT_USER@$ROBOT_HOST" true 2>&1 \
              | grep -m1 'Authentications that can continue' | sed 's/.*continue: //')
    err "could not install the key on $ROBOT_HOST"
    case "$methods" in
        *password*) err "password auth IS offered ($methods), so '$ROBOT_USER' or its password is wrong."
                    err "the factory default is 123; this unit may differ — retry with --user/--pass, or ask whoever set it up." ;;
        *)          err "only ($methods) offered — password auth is off on this unit." ;;
    esac
    err "last resort: USB-C to HDMI plus a keyboard for a local console, then add your key by hand."
    exit 1
}

# One password prompt for the whole run; every later call rides the key.
ensure_key_access() {
    if rsh true 2>/dev/null; then ok "key access already works"; return; fi
    [[ "$DRY_RUN" == "1" ]] && { dimt "[dry-run] ssh-copy-id $ROBOT_USER@$ROBOT_HOST"; return 0; }
    info "installing your key — password is the factory default (${ROBOT_PASS})"
    if has_cmd sshpass; then
        sshpass -p "$ROBOT_PASS" ssh-copy-id -o StrictHostKeyChecking=no \
            "$ROBOT_USER@$ROBOT_HOST" >/dev/null 2>&1 || die "ssh-copy-id failed"
    else
        ssh-copy-id -o StrictHostKeyChecking=no "$ROBOT_USER@$ROBOT_HOST" </dev/tty \
            || key_access_failed
    fi
    rsh true || die "key installed but ssh still fails"
    ok "key access established"
}

# ─── step 2: robot joins wifi ─────────────────────────────────────────────────
# wifi-sec.key-mgmt wpa-psk forces WPA2; 20.04's wpa_supplicant fails the WPA3 handshake.
join_wifi() {
    if [[ "$(rsh "nmcli -t -f DEVICE,STATE device status | grep '^wlan0:' | cut -d: -f2")" == "connected" ]]; then
        ok "robot wifi already connected"
    else
        info "joining robot to '$SSID'"
        rsudo "nmcli connection delete '$SSID'" >/dev/null 2>&1 || true
        rsudo "nmcli connection add type wifi ifname wlan0 con-name '$SSID' \
               ssid '$SSID' wifi-sec.key-mgmt wpa-psk wifi-sec.psk '$PSK'" >/dev/null \
            || die "could not create the wifi profile"
        rsudo "nmcli connection up '$SSID'" >/dev/null \
            || die "wifi failed to come up — check the password and that '$SSID' is in range"
    fi
    capture_wifi_ip
}

capture_wifi_ip() {
    [[ "$DRY_RUN" == "1" ]] && { WIFI_IP="10.0.0.x"; trace "capture wifi ip"; return 0; }
    WIFI_IP=$(rsh "ip -4 -br addr show wlan0 | awk '{print \$3}' | cut -d/ -f1" | tr -d '[:space:]')
    # A bare dotted quad or nothing: anything else means stray output rode in with the value.
    if [[ ! "$WIFI_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        die "expected an IPv4 address from wlan0, got: '${WIFI_IP:-<empty>}'"
    fi
    ok "robot wifi address: $WIFI_IP"
}

# ─── step 3: prove wifi before the cable comes out ────────────────────────────
prove_wifi_ssh() {
    ROBOT_HOST="$WIFI_IP"
    rsh true || die "wifi ssh failed — leave the cable in and investigate"
    ok "wifi ssh proven — the cable is now optional"
}

# ─── step 4: install dimos ────────────────────────────────────────────────────
# --project-dir is what opts into the full python project; non-interactive alone gives CLI+desktop.
install_dimos() {
    info "installing DimOS on the robot (several minutes, one time)"
    rsh "bash <(curl -fsSL https://pub-4767fdd15e6a41b6b2ce2558d71ec8d9.r2.dev/install.sh) \
         --project-dir /home/$ROBOT_USER/dimos --mode dev --extras unitree --non-interactive" \
        || die "installer failed — rerun with --dry-run and run the printed command by hand"
    ok "DimOS installed"
}

# Public repos fetched over ssh fail on a robot with no github key.
fix_git_transport() {
    rsh "git config --global url.'https://github.com/'.insteadOf 'ssh://git@github.com/'" || true
}

# A fresh login shell, not the install shell: CYCLONEDDS_HOME is exported after the installer's own check.
verify_install() {
    info "verifying in a fresh login shell"
    rsh_script <<'REMOTE' || warn "verification incomplete"
source "$HOME/dimos/.venv/bin/activate" 2>/dev/null
echo "CYCLONEDDS_HOME=${CYCLONEDDS_HOME:-UNSET}"
python -c 'import cyclonedds; print("cyclonedds OK")' 2>&1 | tail -1
python -c 'import unitree_sdk2py; print("unitree_sdk2py OK")' 2>&1 | tail -1
dimos --help >/dev/null 2>&1 && echo "dimos CLI OK" || echo "dimos CLI FAILED"
dim doctor 2>&1 | tail -20
REMOTE
}

# ─── device record ────────────────────────────────────────────────────────────
# Unitree's own installer directory is the only place the model is spelled out; version.json has none.
detect_robot() {
    local marker family
    marker=$(rsh "ls -d ~/*_unitree_install 2>/dev/null | head -1" | xargs -r basename)
    family=$(rsh "ls ~/unitree_sdk2-main/example 2>/dev/null | grep -qx humanoid && echo humanoid || echo other")
    ROBOT_MODEL="${marker%%_unitree_install}"
    if [[ -z "$ROBOT_MODEL" ]]; then ROBOT_MODEL="unknown"; fi
    ok "robot: ${ROBOT_MODEL:-unknown} (${family})"
}

# Runs BEFORE the long install: the wifi lease can move mid-install, a tailnet address cannot.
setup_tailscale() {
    if [[ "$TAILSCALE" == "0" ]]; then info "tailscale skipped (--no-tailscale)"; return 0; fi
    local mac
    mac=$(rsh "cat /sys/class/net/wlan0/address" | tr -d ': \n')
    # Every fresh G1 is named "ubuntu"; model+mac keeps nine of them apart in MagicDNS.
    TS_HOST="${ROBOT_MODEL//_/-}-${mac: -6}"
    if ! rsh "command -v tailscale >/dev/null 2>&1"; then
        info "installing tailscale"
        rsh "curl -fsSL https://tailscale.com/install.sh -o /tmp/ts-install.sh" || die "could not fetch tailscale installer"
        rsudo "sh /tmp/ts-install.sh" >/dev/null || die "tailscale install failed"
    fi
    if [[ -n "$TS_AUTHKEY" ]]; then
        rsudo "tailscale up --authkey '$TS_AUTHKEY' --hostname '$TS_HOST' --accept-routes" >/dev/null \
            || die "tailscale up failed — is the auth key valid and unexpired?"
        ok "joined the tailnet as $TS_HOST"
    else
        TS_LOGIN_URL=$(rsudo "timeout 25 tailscale up --hostname '$TS_HOST'" 2>&1 \
                       | grep -oE 'https://login\.tailscale\.com/\S+' | head -1 || true)
        warn "no --ts-authkey: authorize this robot once at ${TS_LOGIN_URL:-<no url returned>}"
    fi
    TS_IP=$(rsh "tailscale ip -4 2>/dev/null" | head -1 | tr -d '[:space:]')
    if [[ -n "$TS_IP" ]]; then ok "tailnet address: $TS_IP (survives DHCP)"; fi
}

# usb0/l4tbr0 would mean future units need no ethernet at all — worth knowing per robot.
write_device_record() {
    [[ "$DRY_RUN" == "1" ]] && { dimt "[dry-run] write device record"; return 0; }
    mkdir -p "$RECORD_DIR"
    local model l4t serial usbnet dimos_rev mac
    model=$(rsh "tr -d '\0' < /proc/device-tree/model 2>/dev/null" || echo unknown)
    l4t=$(rsh "cat /etc/nv_tegra_release 2>/dev/null | head -1" || echo unknown)
    serial=$(rsh "tr -d '\0' < /proc/device-tree/serial-number 2>/dev/null" || echo unknown)
    usbnet=$(rsh "ls /sys/class/net | grep -E '^(usb0|l4tbr0)$' | paste -sd, -" || true)
    dimos_rev=$(rsh "git -C ~/dimos rev-parse --short HEAD 2>/dev/null" || echo unknown)
    mac=$(rsh "cat /sys/class/net/wlan0/address 2>/dev/null" || echo unknown)

    local out="$RECORD_DIR/g1-${mac//:/}.json"
    cat > "$out" <<EOF
{
  "robot_model": "$ROBOT_MODEL",
  "jetson_model": "$model",
  "l4t_release": "$l4t",
  "serial": "$serial",
  "wlan0_mac": "$mac",
  "wifi_ip": "$WIFI_IP",
  "tailscale_hostname": "$TS_HOST",
  "tailscale_ip": "$TS_IP",
  "jetson_wired_ip": "$JETSON_IP",
  "usb_device_mode_ifaces": "${usbnet:-none}",
  "dimos_rev": "$dimos_rev",
  "ssid": "$SSID",
  "brought_up_by": "$(whoami)@$(hostname)",
  "bringup_git_rev": "$(git -C "$(dirname "$0")" rev-parse --short HEAD 2>/dev/null || echo unknown)"
}
EOF
    ok "device record: $out"
    if [[ -n "$usbnet" ]]; then
        ok "this unit exposes USB device-mode net ($usbnet) — future bring-ups can skip ethernet"
    fi
}

print_next_steps() {
    printf "\n%sBrought up.%s Robot is at %s%s%s\n\n" "$BOLD" "$RESET" "$BOLD" "$WIFI_IP" "$RESET"
    printf "The robot has NOT been stood up. That is a human step:\n\n"
    dimt "  # gantry the robot, controller in hand, area clear"
    dimt "  ssh -L 3030:localhost:3030 $ROBOT_USER@$WIFI_IP"
    dimt "  cd ~/dimos && source .venv/bin/activate && dimos --rerun-host 0.0.0.0 run unitree-g1"
    printf "\nThen from this laptop:\n\n"
    dimt "  dimos-viewer --connect rerun+http://$WIFI_IP:9877/proxy --ws-url ws://$WIFI_IP:3030/ws"
    printf "\n"
}

main() {
    parse_args "$@"
    check_prereqs
    phase "1/12  wifi credentials from this machine"; resolve_wifi
    phase "2/12  wired interface";                    detect_iface
    phase "3/12  waiting for the cable";              wait_for_carrier
    phase "4/12  laptop onto the robot subnet";       ensure_wired_profile
    phase "5/12  reaching the jetson";                wait_for_jetson
    phase "6/12  key access";                         ensure_key_access
    phase "7/12  robot joins wifi";                   join_wifi
    phase "8/12  untethered ssh";                     prove_wifi_ssh
    phase "9/12  identifying the robot";              detect_robot
    phase "10/12 tailscale";                          setup_tailscale
    phase "11/12 git transport + dimos install";      fix_git_transport; install_dimos
    phase "12/12 verify + device record";             verify_install; write_device_record
    print_next_steps
}

main "$@"
