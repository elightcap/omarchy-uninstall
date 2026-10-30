# omarchy-uninstall

Takes [Omarchy](https://omarchy.org) back off a computer and leaves plain Arch Linux behind, booting to a text login.

Omarchy is a layer on top of Arch: its own packages, a default set of desktop packages and apps, a package repository and signing key, system configuration and services written by its installer, a factory-reset snapshot, and configuration seeded into each user's home. This command reverses that layer and keeps the base system: the disk layout and encryption, the Limine bootloader and snapper snapshots, the kernel, firmware and hardware fixes, NetworkManager, and everything you installed yourself.

## Status

Early, but it has run for real. `test/vm` boots the installed Omarchy VM image that nightly.omarchy.org publishes (the one Omarchy's own CI tests on) under KVM, runs the uninstall in it, and boots the leftover disk again through UEFI firmware, Limine and the rebuilt UKI. That run passes against Omarchy 4.0.6: the machine comes back on the stock Arch kernel with Arch's os-release, no Omarchy packages, no orphans, no failed units, a working network and package manager, a single UKI under an "Arch Linux" boot entry, and the user's Omarchy configuration moved aside. The pieces of pure logic (repository editing, boot-config capture, boot-menu editing, home-directory retirement) have unit tests besides.

What that run does not cover: an encrypted root (the published image is unencrypted; the LUKS hooks are captured the same way, but nothing has proven them), a machine upgraded from an older Omarchy rather than installed fresh, aarch64, and hardware with its own drivers. Treat those as untested.

## Usage

See the plan first. This needs no root and works from a desktop terminal:

```
./omarchy-uninstall --dry-run
```

Then log out of the desktop, switch to a console (`Ctrl+Alt+F3`), log in and run it for real. It asks for sudo itself and refuses to run while a desktop session is open, since it removes the desktop it would be running in.

```
./omarchy-uninstall
```

`--yes` skips the confirmation and the reboot question.

## What it does, in order

1. Writes the mkinitcpio HOOKS and limine-entry-tool settings that Omarchy's packages carry into files nothing owns, minus Plymouth and branding, so an encrypted root still unlocks once the packages are gone. A machine on `linux-omarchy` gets the stock `linux` kernel first.
2. Marks the base system explicitly installed (Limine, snapper, btrfs-progs, the kernel, cryptsetup, NetworkManager, sudo, and the ISO's base-system list) so the recursive removal cannot cascade into it.
3. Disables the services Omarchy enabled, then removes Omarchy's packages and its default package set. It keeps the console essentials from that set (`base-devel`, `git`, `less`, `man-db`, `vi`, `inetutils`), networking (`networkmanager`, `wireless-regdb`) and `dosfstools`, and makes sure the dependency sweep spares `openssh`.
4. Drops the `[omarchy]` repository sections and signing key, and restores an Arch mirrorlist.
5. Reverts the system files Omarchy's setup wrote outside any package: `/etc/os-release`, `nsswitch.conf`, the faillock limits, the PAM PATH line, `/etc/skel/.bashrc`, and the stray files and dangling unit links.
6. Moves each user's Omarchy configuration into `~/omarchy-uninstalled-<timestamp>`. Nothing in a home is deleted except caches. A seeded config file is moved only if it still references Omarchy; one that doesn't (your git config, say) stays. Chromium's profile stays regardless.
7. Rebuilds the boot files with `limine-update`, prunes the UKIs it no longer lists, and deletes the `@factory` snapshot.
8. Lists the installed packages that came only from Omarchy's repository and will stop updating. `limine-mkinitcpio-hook` and `limine-snapper-sync` are the ones that matter; both are on the AUR.

Up to the package removal a failure stops the run with nothing irreversible done. After it, each step is best effort and reported, since the command's own package is gone by then. The log is `/var/log/omarchy-uninstall.log`.

## Limits

- x86 and plain aarch64 only. Apple Silicon, Snapdragon, N1x and GB10 machines get their kernel and boot chain from Omarchy's platform packages, so there is no plain Arch Linux underneath to return to.
- Hardware fixes, optional setups (sshd hardening, fingerprint, hibernation), Docker's data and mise's tools are left as they are.
- An Omarchy old enough to lack `omarchy-hw-platform` is handled on x86 only.

## Tests

Unit tests, a few seconds:

```
bash test/uninstall-test.sh
```

The real thing, in a throwaway VM on this machine (needs `qemu-system-x86_64`, `edk2-ovmf`, `jq`, `curl`, `socat` and KVM; the 4.5 GB image is cached under `~/.cache/omarchy-uninstall`):

```
test/vm
```

It takes a couple of minutes once the image is cached and prints a run directory holding the uninstall's output and log, the system state before and after, the serial logs and screenshots of both boots. A failed run keeps its disk there for a look (`--keep` keeps a passing one too), and `--boot kernel` loads the kernel directly for the first boot the way Omarchy's CI does.
