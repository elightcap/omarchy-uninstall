#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  local description="$1" detail="${2:-}"
  [[ -n $detail ]] && printf '%s\n' "$detail" >&2
  printf 'not ok - %s\n' "$description" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The production functions and the lists they read, without the elevation or
# the uninstall itself.
awk '
  /^[A-Z_]+=\(/ { print; next }
  /^[a-z_]+\(\) \{/ { copying = 1 }
  copying { print }
  /^}/ { copying = 0 }
' "$ROOT/omarchy-uninstall" >"$tmp/functions"

# Runs a snippet against the production functions with the output helpers
# quiet and every command run for real on a disposable tree.
with_uninstall_functions() {
  bash -c '
    set -euo pipefail
    source "$1/functions"
    dry_run=0
    STAMP=test
    LOG_FILE=/dev/null
    log() { :; }
    say() { :; }
    warn() { printf "%s\n" "$1" >&2; }
    run() { "$@"; }
    eval "$2"
  ' _ "$tmp" "$1"
}

# Repository sections: every [omarchy*] one goes, everything else stays as it was.
cat >"$tmp/pacman.conf" <<'EOF'
[options]
HoldPkg = pacman glibc
SigLevel = Required DatabaseOptional

# pacman searches repositories in the order defined here
[omarchy]
Server = https://mirror.example.cn/omarchy/stable/$arch
Server = https://pkgs.omarchy.org/stable/$arch

[core]
Include = /etc/pacman.d/mirrorlist

[omarchy-aarch64]
Server = https://pkgs.omarchy.org/aarch64/$arch

[pritunl]
Server = https://repo.pritunl.com/stable/pacman
SigLevel = Never
EOF
with_uninstall_functions "strip_omarchy_repos $tmp/pacman.conf"
expected=$(cat <<'EOF'
[options]
HoldPkg = pacman glibc
SigLevel = Required DatabaseOptional

# pacman searches repositories in the order defined here
[core]
Include = /etc/pacman.d/mirrorlist

[pritunl]
Server = https://repo.pritunl.com/stable/pacman
SigLevel = Never
EOF
)
[[ $(<"$tmp/pacman.conf") == "$expected" ]] || fail "omarchy repository sections leave pacman.conf and the rest stays" "$(<"$tmp/pacman.conf")"
pass "omarchy repository sections leave pacman.conf and the rest stays"

# Boot configuration: the hooks the owned drop-in resolves to are kept without
# Plymouth, and the entry settings without branding or kernel parameters.
etc="$tmp/etc"
mkdir -p "$etc/mkinitcpio.conf.d" "$etc/limine-entry-tool.d"
cat >"$etc/mkinitcpio.conf" <<'EOF'
MODULES=()
HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)
EOF
cat >"$etc/mkinitcpio.conf.d/00-omarchy-hooks.conf" <<'EOF'
HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)
EOF
cat >"$etc/limine-entry-tool.d/omarchy-defaults.conf" <<'EOF'
TARGET_OS_NAME="Omarchy"
KERNEL_CMDLINE[default]+=" quiet splash loglevel=0"
CUSTOM_UKI_NAME="omarchy"
ENABLE_LIMINE_FALLBACK=yes
FIND_BOOTLOADERS=yes
MAX_SNAPSHOT_ENTRIES=6
EOF
printf 'ENABLE_UKI=yes\n' >"$etc/limine-entry-tool.d/omarchy-uki.conf"
with_uninstall_functions "owned_mkinitcpio=($etc/mkinitcpio.conf.d/00-omarchy-hooks.conf)
  owned_limine=($etc/limine-entry-tool.d/omarchy-defaults.conf $etc/limine-entry-tool.d/omarchy-uki.conf)
  keep_boot_config $etc"
grep -qx 'HOOKS=(base udev keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)' \
  "$etc/mkinitcpio.conf.d/00-hooks.conf" || fail "the hooks the owned drop-in set are kept without plymouth" "$(cat "$etc/mkinitcpio.conf.d/00-hooks.conf")"
pass "the hooks the owned drop-in set are kept without plymouth"
settings=$(grep -v '^#' "$etc/limine-entry-tool.d/10-boot-entries.conf")
[[ $settings == $'ENABLE_UKI=yes\nENABLE_LIMINE_FALLBACK=yes\nFIND_BOOTLOADERS=yes\nMAX_SNAPSHOT_ENTRIES=6' ]] ||
  fail "the boot entry settings are kept without branding or kernel parameters" "$settings"
pass "the boot entry settings are kept without branding or kernel parameters"

# Hooks in the main file alone still lose plymouth; without it, nothing is written.
rm -f "$etc/mkinitcpio.conf.d/00-hooks.conf"
printf 'HOOKS=(base udev plymouth block encrypt filesystems fsck)\n' >"$etc/mkinitcpio.conf"
with_uninstall_functions "owned_mkinitcpio=(); owned_limine=(); keep_boot_config $etc"
grep -qx 'HOOKS=(base udev block encrypt filesystems fsck)' "$etc/mkinitcpio.conf.d/00-hooks.conf" ||
  fail "plymouth leaves hooks the main file sets" "$(cat "$etc/mkinitcpio.conf.d/00-hooks.conf")"
pass "plymouth leaves hooks the main file sets"
rm -f "$etc/mkinitcpio.conf.d/00-hooks.conf"
printf 'HOOKS=(base udev block encrypt filesystems fsck)\n' >"$etc/mkinitcpio.conf"
with_uninstall_functions "owned_mkinitcpio=(); owned_limine=(); keep_boot_config $etc"
[[ ! -e $etc/mkinitcpio.conf.d/00-hooks.conf ]] || fail "hooks that neither an owned drop-in nor plymouth shaped are left alone"
pass "hooks that neither an owned drop-in nor plymouth shaped are left alone"

# A home directory: Omarchy's own directories and the seeded files that still
# point at Omarchy move to the backup, the owner's files stay, links into
# Omarchy's trees go, and .bashrc is stock again.
home="$tmp/home"
mkdir -p "$home/.config/alacritty" "$home/.config/git" "$home/.config/chromium/Default" "$home/.config/omarchy/themes/mine" \
  "$home/.local/state/omarchy/current" "$home/.cache/omarchy" "$home/.claude/skills" "$home/.config/systemd/user/default.target.wants" \
  "$home/.config/btop/themes"
printf 'import = ["~/.config/omarchy/current/theme/alacritty.toml"]\n' >"$home/.config/alacritty/alacritty.toml"
printf '[user]\nname = Owner\n' >"$home/.config/git/config"
printf '{"extensions":{"path":"/usr/share/omarchy/default/chromium/extensions/copy-url"}}\n' >"$home/.config/chromium/Default/Preferences"
touch "$home/.config/omarchy/themes/mine/colors.toml" "$home/.local/state/omarchy/current/theme.name" "$home/.cache/omarchy/selector"
# shellcheck disable=SC2016  # the fixture sources the variable, not its value
printf 'source "$OMARCHY_PATH/default/bash/rc"\nalias p=python\n' >"$home/.bashrc"
ln -s /usr/share/omarchy/default/agents/skills/omarchy "$home/.claude/skills/omarchy"
ln -s "$tmp/elsewhere" "$home/.claude/skills/mine"
ln -s /usr/lib/systemd/user/omarchy-gone.service "$home/.config/systemd/user/default.target.wants/omarchy-gone.service"
ln -s "$home/.local/state/omarchy/current/theme/btop.theme" "$home/.config/btop/themes/current.theme"
with_uninstall_functions "OMARCHY_PATH=$tmp/checkout
  seeded=(.config/alacritty/alacritty.toml .config/git/config .config/chromium/Default/Preferences)
  retire_user_config owner $(id -u) $(id -g) $home"
backup="$home/omarchy-uninstalled-test"
[[ -f $backup/.config/alacritty/alacritty.toml && ! -e $home/.config/alacritty ]] ||
  fail "a seeded file that points at Omarchy moves to the backup and its emptied directory goes"
pass "a seeded file that points at Omarchy moves to the backup and its emptied directory goes"
[[ -f $home/.config/git/config && ! -e $backup/.config/git ]] || fail "a seeded file that never mentioned Omarchy stays"
pass "a seeded file that never mentioned Omarchy stays"
[[ -f $home/.config/chromium/Default/Preferences && ! -e $backup/.config/chromium ]] ||
  fail "the browser profile stays even though it names Omarchy's extensions"
pass "the browser profile stays even though it names Omarchy's extensions"
[[ -f $backup/.config/omarchy/themes/mine/colors.toml && ! -e $home/.config/omarchy ]] || fail "Omarchy's own directories move whole"
[[ -f $backup/.local/state/omarchy/current/theme.name && ! -e $home/.local/state/omarchy ]] || fail "Omarchy's state directory moves whole"
pass "Omarchy's own directories move whole"
[[ ! -e $home/.cache/omarchy ]] || fail "the cache is deleted"
pass "the cache is deleted"
[[ -f $backup/.bashrc ]] || fail "the .bashrc that sourced Omarchy is kept in the backup"
grep -q 'alias p=python' "$backup/.bashrc" || fail "the owner's .bashrc additions are in the backup"
{ ! grep -q omarchy "$home/.bashrc" && grep -q 'PS1=' "$home/.bashrc"; } || fail ".bashrc is the stock one again"
pass ".bashrc that sourced Omarchy is replaced by the stock one, the old copy kept"
[[ ! -L $home/.claude/skills/omarchy && -L $home/.claude/skills/mine ]] || fail "only the skill links into Omarchy's tree go"
pass "only the skill links into Omarchy's tree go"
[[ ! -L $home/.config/systemd/user/default.target.wants/omarchy-gone.service ]] || fail "dangling user unit links go"
pass "dangling user unit links go"
[[ ! -L $home/.config/btop/themes/current.theme ]] || fail "links into the moved directories go"
pass "links into the moved directories go"
[[ $(stat -c %u "$backup/.config/alacritty") == "$(id -u)" ]] || fail "the backup belongs to the user"
pass "the backup belongs to the user"
