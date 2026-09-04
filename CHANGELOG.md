# Changelog

## [Unreleased]

### Fixed

- `unpin install usbutils` now creates the commands. In the v019-1 release it
  created only `usbutils` itself: the list of program names never made it into
  the published binary, so `lsusb` was installed nowhere.
- The Windows binary carried the manual page for `usbhid-dump`, a program it
  has not got — it needs `sigaction`/`SIGUSR1`, which Windows does not provide.
  The page is gone; `lsusb` is what the Windows binary has, and now the only
  thing it documents.

### Changed

- The README said this installs "the `lsusb` command". On Linux and macOS it
  installs two, `lsusb` and `usbhid-dump`; only the Windows binary has just the
  one. Both are named now, with the reason for the difference.
- The README also said a bare `usbutils` runs `lsusb`. It lists the programs
  instead — `usbutils` is not itself one of them, which is the catalog's rule.
  Usage shows the form that works.
