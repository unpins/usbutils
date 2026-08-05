# Fold usbutils into ONE multicall binary at $out/bin/usbutils that dispatches
# `lsusb` and `usbhid-dump` by argv[0] (a bare/unknown `usbutils` is not a
# program, so it lists). `lib.withAliases` then embeds `lsusb` / `usbhid-dump` as
# UNPIN_META aliases so unpin recreates the argv[0] shims on PATH.
#
# Why source-level fold (not pciutils' objcopy-on-.o route): usbutils builds
# with meson, which hides the per-target objects and owns the link line (static
# libusb + its frameworks on darwin, iconv, ...). Folding at the source level
# lets meson keep doing the link: lsusb and usbhid-dump share no .c file and
# collide only on `main` (lsusb's helpers are static; usbhid-dump's globals are
# all `uhd_*`), so we just rename each main and build a single executable from
# both source sets + the argv[0] dispatcher (lib.multicallTableDispatcherC).
#
# Self-contained names: usbutils 019 resolves names only via udev's binary hwdb
# (Linux-only, no Windows/macOS analogue). ./names.c restores the historical
# usb.ids *text* parser fed the database EMBEDDED in the binary (xxd -i of
# hwdata's usb.ids), and libudev is dropped -- names resolve with no companion
# file on every OS, exactly as the unpins pciutils embeds pci.ids.
#
# Cross-platform gating comes from the Homebrew portable.patch (applied on ALL
# platforms here): `-Dwith_sysfs` / `-Dwith_tree_mode` add sysfs.c (manufacturer/
# product string fallback) and lsusb-t.c (`lsusb -t` device tree). Both read
# /sys directly and pull <linux/limits.h>, so they are Linux-only; on macOS/
# Windows they are gated off (no /sys -> no `-t`, no string fallback), and
# lsusb.c / names.c #ifdef those call sites. names_init() is always called (the
# embed parser), so vendor/product names resolve everywhere.
#
# Windows-only now (the native + darwin `build` self-folds via the unpin-llvm
# engine, like pciutils/htop). The residual isDarwin branches are inert under
# the sole windowsBuild caller. isWindows comes from the INPUT derivation's
# stdenv (under windowsBuild `pkgs` is the x86_64-linux root — the cross lives
# inside mingwStaticCross — so `pkgs.stdenv` would wrongly say "not Windows").
{ lib }:
{ pkgs, usbutils }:
let
  isDarwin = usbutils.stdenv.hostPlatform.isDarwin or false;
  isWindows = usbutils.stdenv.hostPlatform.isWindows or false;
  linuxLike = !isDarwin && !isWindows;
  boolFlag = b: if b then "true" else "false";

  # usbhid-dump uses sigaction / sigaddset / SIGUSR1|2 (and would need a
  # per-device WinUSB driver to do anything) -- none of which mingw has -- so on
  # Windows the multicall folds lsusb only. lsusb is the tool that matters: it
  # enumerates + resolves names driverless via libusb's WinUSB backend.
  withHid = !isWindows;
  applets = [ "lsusb" ] ++ lib.optional withHid "usbhid-dump";
  srcExpr =
    if withHid
    then "lsusb_sources + usbhid_sources + files('multicall/dispatcher.c')"
    else "lsusb_sources + files('multicall/dispatcher.c')";

  # libusb for THIS platform comes from the input derivation's own deps (the
  # native pkgsStatic puts it in propagatedBuildInputs; the mingw cross in
  # buildInputs); just drop python3 (only there for lsusb.py, which we don't
  # ship) so the build doesn't have to produce a static/cross CPython.
  keepLibusb = builtins.filter
    (x: let n = x.pname or x.name or ""; in n == "libusb" || lib.hasPrefix "libusb" n)
    ((usbutils.buildInputs or [ ]) ++ (usbutils.propagatedBuildInputs or [ ]));

  multicall = usbutils.overrideAttrs (old: {
    pname = "usbutils-multi";
    outputs = [ "out" ];

    # nixpkgs marks usbutils linux+darwin only; we build it for mingw too.
    meta = (old.meta or { }) // { platforms = lib.platforms.all; };

    # Replace nixpkgs' patch set: fix-paths.patch only rewrites lsusb.py (which
    # we drop); the Homebrew portable.patch (with_sysfs/with_tree_mode/with_udev
    # gating) + our usbmisc.c mingw guards (nl_langinfo / readlink `-D` path)
    # apply on every platform -- both are inert (#ifdef-guarded) off-Windows.
    patches = [ ./portable.patch ./usbutils-win.patch ];

    # On mingw, usbmisc.c's UTF-16LE -> UTF-8 string conversion needs libiconv
    # (it is in libc on glibc/musl/macOS, hence native needs nothing extra).
    buildInputs = keepLibusb
      ++ lib.optional isWindows (lib.mingwStaticCross pkgs).libiconv;
    propagatedBuildInputs = [ ];

    nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.buildPackages.xxd ];

    # sysfs / tree-mode are Linux-only (read /sys, include <linux/limits.h>).
    mesonFlags = (old.mesonFlags or [ ]) ++ [
      "-Dwith_sysfs=${boolFlag linuxLike}"
      "-Dwith_tree_mode=${boolFlag linuxLike}"
    ];

    doCheck = false;

    postPatch = (old.postPatch or "") + ''
      # Real usb.ids text parser (embed-backed) instead of the Homebrew no-udev
      # stub, and bake hwdata's usb.ids in next to it.
      cp ${./names.c} names.c
      xxd -i -n unpin_usb_ids \
        ${pkgs.buildPackages.hwdata}/share/hwdata/usb.ids > usb_ids.h

      # Always take the names.c branch + define HAVE_UDEV (which gates the
      # names_init()/names_exit() calls in lsusb.c) -- our names.c is the embed
      # parser, not the udev backend, so libudev is never linked.
      substituteInPlace meson.build \
        --replace "if get_option('with_udev') and libudev.found()" "if true"

      # Rename each tool's main, drop the two separate executables, and append a
      # single `usbutils` from the applicable source sets + the argv[0]
      # dispatcher (usbhid-dump folded in only off-Windows).
      substituteInPlace lsusb.c \
        --replace "int main(int argc, char *argv[])" "int lsusb_main(int argc, char *argv[])"
      substituteInPlace usbhid-dump/usbhid-dump.c \
        --replace "main(int argc, char **argv)" "usbhid_dump_main(int argc, char **argv)"
      substituteInPlace meson.build \
        --replace "executable('lsusb', lsusb_sources, dependencies: [libusb, libudev, libiconv], install: true)" "" \
        --replace "executable('usbhid-dump', usbhid_sources, dependencies: libusb, install: true)" ""
      printf "\nexecutable('usbutils', %s, dependencies: [libusb, libiconv], install: true)\n" \
        "${srcExpr}" >> meson.build

      # Dispatcher reads multicall/applets.list as a TSV of <applet>\t<fn-base>
      # (C symbol <fn-base>_main). The source-level rename above turns each
      # tool's main into <tool>_main, so fn-base IS the tool name — one
      # self-mapping row per applet (lsusb only on Windows; usbhid-dump folded
      # in off-Windows).
      mkdir -p multicall
      for t in ${lib.concatStringsSep " " applets}; do printf '%s\t%s\n' "$t" "$t"; done > multicall/applets.list
${lib.multicallTableDispatcherC { name = "usbutils"; }}
    '';

    # One binary: usbutils. Applets are argv[0] aliases (withAliases), not files.
    # Keep $out/share/man/man8 for withMan; drop scripts/extra tools.
    postInstall = ''
      rm -f $out/bin/usb-devices $out/bin/lsusb.py $out/bin/usbreset
      rm -rf $out/share/man/man1
    '';
  });

  aliased = lib.withAliases pkgs
    {
      primary = "usbutils";
      aliases = applets;
    }
    multicall;
in
aliased
