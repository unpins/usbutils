# usbutils

[usbutils](https://github.com/gregkh/usbutils) — `lsusb`, the tool that lists the USB devices connected to your system, in a single self-contained binary built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/usbutils/actions/workflows/usbutils.yml/badge.svg)](https://github.com/unpins/usbutils/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install usbutils`.

## Usage

Run a program with [unpin](https://github.com/unpins/unpin):

```bash
unpin usbutils --unpin-program=lsusb            # list USB devices
unpin usbutils --unpin-program=lsusb -v         # verbose, with descriptors
unpin usbutils --unpin-program=usbhid-dump      # dump HID reports (Linux, macOS)
```

A bare `unpin usbutils` lists the programs it holds.

To install the commands onto your PATH:

```bash
unpin install usbutils
```

This creates `lsusb`, and `usbhid-dump` on Linux and macOS — it needs `sigaction`/`SIGUSR1`, which Windows has not, so the Windows binary carries `lsusb` alone. `unpin info usbutils` lists every command.

Listing devices needs no privilege and no driver on Linux and Windows — no `sudo`, no administrator. Vendor, product and class names are resolved from a built-in database, so the output is readable out of the box.

## Build locally

```bash
nix build github:unpins/usbutils
./result/bin/usbutils --version
```

Or run directly:

```bash
nix run github:unpins/usbutils -- --version
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/usbutils/releases) page has standalone binaries for manual download.

## Build notes

- `usbutils` is the canonical binary; `lsusb` is the command you run, recreated
  on PATH by `unpin install`. On Linux and macOS it also carries `usbhid-dump`
  (HID report-descriptor dumps); the Windows build ships `lsusb` only.
- The USB ID database (`usb.ids`) is embedded, so names resolve with no
  companion file on every OS. The man pages are embedded too —
  `unpin man usbutils lsusb`.
- `lsusb` gets the device list and descriptors from
  [libusb](https://libusb.info), whose backends are cross-platform: Linux usbfs,
  Windows WinUSB (via `cfgmgr32`), macOS IOKit. The Windows build is cross-built
  with mingw and has no companion DLLs.
- Modern upstream usbutils resolves names only through udev's binary hwdb — a
  Linux-only database with no Windows/macOS counterpart. This build restores the
  historical `usb.ids` text parser, feeds it the embedded database, and drops
  the libudev dependency; that is also what makes the macOS and Windows builds
  possible.
- **Linux**: lists devices and resolves names with no privilege; `lsusb -t`
  (device tree) and the per-device string fallback read `/sys` directly.
  `usbhid-dump` opens and claims the device, which needs root.
- **Windows**: `lsusb` enumerates and reads device/configuration descriptors
  with no driver. A device's own string descriptors (its self-reported
  manufacturer/product text) need the device opened, which needs a per-device
  WinUSB driver — without one those fields show their index only, while the
  vendor/product names still come from the embedded database.
- **macOS**: lists via IOKit; `lsusb -t` is unavailable (no `/sys`). A normal
  Terminal session works; a headless SSH session cannot load the IOKit USB
  plugin (`kIOReturnNoResources`) and lists nothing.
