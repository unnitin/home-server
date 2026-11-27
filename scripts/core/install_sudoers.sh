#!/usr/bin/env bash
# Install the scoped sudo rule, /etc/sudoers.d/homelab (docs/mcp-refactor/05).
#
#   sudo scripts/core/install_sudoers.sh [--yes]   install it, or bring it up to date
#   scripts/core/install_sudoers.sh --print        show what would be installed
#   scripts/core/install_sudoers.sh --check        is it installed and current?
#   sudo scripts/core/install_sudoers.sh --remove  take it away
#
# The rule lets your user run exactly the pmset commands of the manifest's
# power profile (power: in config/homelab.yaml) without a password, so the
# power_ensure tool can put a drifted setting back. Nothing else: no
# wildcards, no shell, and no rule for diskutil at all. The text comes from
# `python3 -m homelab sudoers render`, the same list homelab.exec checks every
# sudo call against.
#
# The file is checked with `visudo -c` before it's installed, and the whole sudo
# configuration again after; if that fails, the file is removed. Re-run it after
# changing the power profile.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=environment.sh
source "$SCRIPT_DIR/environment.sh"

TARGET="${HOMELAB_SUDOERS_FILE:-/etc/sudoers.d/homelab}"
VISUDO="${VISUDO:-/usr/sbin/visudo}"
if [[ -n "${HOMELAB_PYTHON:-}" ]]; then
    PYTHON="$HOMELAB_PYTHON"
elif [[ -x /opt/homebrew/bin/python3.11 ]]; then
    PYTHON=/opt/homebrew/bin/python3.11
else
    PYTHON=python3
fi
USER_NAME="${SUDO_USER:-$(id -un)}"
TESTING=false
[[ "${TEST_MODE:-0}" == "1" ]] && TESTING=true

MODE=install
YES=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --print) MODE=print ;;
        --check) MODE=check ;;
        --remove) MODE=remove ;;
        --yes) YES=true ;;
        -h | --help) sed -n '2,19p' "$0"; exit 0 ;;
        *) log_error "Unknown option: $1 (try --help)"; exit 2 ;;
    esac
    shift
done

# Python runs as you, never as root: it would leave root-owned files in the repo.
as_user() {
    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]] && ! $TESTING; then
        sudo -u "$SUDO_USER" "$@"
    else
        "$@"
    fi
}
render() { (cd "$HOMELAB_REPO" && as_user "$PYTHON" -m homelab sudoers render --user "$USER_NAME"); }

need_root() {
    if [[ $EUID -ne 0 ]] && ! $TESTING; then
        log_error "Run it with sudo: sudo $0${1:+ $1}"
        exit 1
    fi
}

case "$MODE" in
    print)
        render
        exit 0
        ;;
    check)
        (cd "$HOMELAB_REPO" && as_user "$PYTHON" -m homelab sudoers check)
        exit $?
        ;;
    remove)
        need_root --remove
        if [[ -f "$TARGET" ]]; then
            rm -f "$TARGET"
            log_info "Removed $TARGET"
        else
            log_info "$TARGET isn't installed"
        fi
        exit 0
        ;;
esac

need_root
if [[ "$USER_NAME" == "root" ]]; then
    log_error "Run it with sudo from your own account, so the rule names your user"
    exit 1
fi

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
render >"$tmp"
if ! "$VISUDO" -cf "$tmp" >/dev/null; then
    log_error "visudo rejected the generated rule; nothing was installed"
    exit 1
fi
echo "The rule for $USER_NAME:"
sed 's/^/    /' "$tmp"
if [[ -f "$TARGET" ]] && cmp -s "$tmp" "$TARGET"; then
    log_info "$TARGET is installed and current"
    exit 0
fi
if ! $YES; then
    read -r -p "Install it as $TARGET? [y/N] " answer
    if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
        log_info "Nothing installed"
        exit 1
    fi
fi
if $TESTING; then
    install -m 0440 "$tmp" "$TARGET"
else
    install -m 0440 -o root -g wheel "$tmp" "$TARGET"
fi
if ! "$VISUDO" -c >/dev/null; then
    rm -f "$TARGET"
    log_error "The sudo configuration didn't check with $TARGET in place; removed it"
    exit 1
fi
log_info "Installed $TARGET: the power_ensure tool can now fix drifted power settings"
