# omarchy-uninstall

Takes [Omarchy](https://omarchy.org) back off a computer and leaves plain Arch Linux behind, booting to a text login.

Omarchy is a layer on top of Arch: its own packages, a default set of desktop packages and apps, a package repository and signing key, system configuration and services written by its installer, a factory-reset snapshot, and configuration seeded into each user's home. This command reverses that layer and keeps the base system: the disk layout and encryption, the Limine bootloader and snapper snapshots, the kernel, firmware and hardware fixes, NetworkManager, and everything you installed yourself.

## Status

Early. The pieces that can be tested without a machine to wreck (repository editing, boot-config capture, home-directory retirement) have unit tests. **No real run has happened yet.** Before trusting it, run it in a disposable VM installed from an Omarchy ISO, reboot, and check that you get a working login, network and `pacman -Syu`.

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
3. Disables the services Omarchy enabled, then removes Omarchy's packages and its default package set, keeping `base-devel`, `networkmanager` and `wireless-regdb`.
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

```
bash test/uninstall-test.sh
```
