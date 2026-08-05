{
  description = "usbutils (lsusb + usbhid-dump) as a single self-contained binary with usb.ids embedded";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # Self-contained static usbutils: ONE multicall binary folding `lsusb` and
  # `usbhid-dump` (./multicall.nix), with both as argv[0] aliases. usb.ids is
  # embedded (./names.c + xxd), so vendor / product / class names resolve
  # everywhere with nothing on disk -- the USB twin of the unpins pciutils.
  #
  # Backends (libusb, unlike pciutils' per-OS native backends):
  #   linux  -> usbfs: lsusb lists devices and resolves names with NO privilege
  #             (descriptors are read from sysfs without opening the device);
  #             `lsusb -t` (tree) + the manufacturer/product string fallback read
  #             /sys directly. usbhid-dump opens+claims the device (needs root).
  #   darwin -> IOKit: lsusb lists + resolves names; `-t` is gated off (no /sys),
  #             as is the sysfs string fallback. usbhid-dump needs the device
  #             not be claimed by the kernel. (Better than lspci on macOS, which
  #             needs root + a boot-arg.)
  #   windows-> WinUSB (later): libusb enumerates + reads device descriptors
  #             driverless, but full `-v` config/string descriptors need a
  #             per-device WinUSB/libusbK driver.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "usbutils";
      # lsusb.c carries SPDX GPL-2.0-or-later (verified upstream); the embedded
      # usb.ids and a stray GPL-2.0-only file don't change the program's license.
      license = "GPL-2.0-or-later";
      smoke = [ "--unpin-program=lsusb" "--version" ];
      # lsusb prints "lsusb (usbutils) 019"; match the suite name.
      smokePattern = "usbutils";

      # Linux AND darwin fold via the unpin-llvm engine (bitcode multicall);
      # Windows folds via the objcopy recipe in ./multicall.nix. The engine
      # compiles usbutils (lsusb + usbhid-dump are separate upstream executables)
      # to bitcode and the standalone self-folds them into one `usbutils` binary.
      # We replicate the app-enabling bits of ./multicall.nix WITHOUT its
      # source-level main-rename/merge: the portable.patch (with_sysfs /
      # with_tree_mode / with_udev gating, makes lsusb buildable off-udev) + the
      # embedded usb.ids (names.c + xxd → names resolve with no companion file) +
      # dropping libudev/python3. Pure C — no requires.cxx.
      engine = "unpin-llvm";
      multicall = {
        # libusb's darwin backend links -lobjc + IOKit / CoreFoundation /
        # Security (configure.ac line 195). The mega relinks lsusb + usbhid-dump
        # from bitcode and can't see meson's own -framework flags, so name them
        # for the darwin self-fold (-lobjc rides in via CoreFoundation's
        # re-export). Cf. htop / pciutils.
        requires.frameworks = [ "IOKit" "CoreFoundation" "Security" ];
        programs = [ { name = "lsusb"; } { name = "usbhid-dump"; } ];
      };

      build = pkgs:
        pkgs.pkgsStatic.usbutils.overrideAttrs (old: {
          # nixpkgs splits a `python` output (for lsusb.py, which we drop);
          # collapse to one.
          outputs = [ "out" ];
          # portable.patch makes lsusb buildable without udev/sysfs hard-deps;
          # usbutils-win.patch's mingw guards are inert off-Windows. Replace
          # nixpkgs' fix-paths.patch (only rewrites lsusb.py, which we drop).
          patches = [ ./portable.patch ./usbutils-win.patch ];
          # libusb only: drop python3 (lsusb.py, not shipped) and let libudev
          # stay unresolved (portable.patch marks it required:false; the embed
          # names.c replaces it).
          buildInputs = builtins.filter
            (x: let n = x.pname or x.name or ""; in
              n == "libusb" || pkgs.lib.hasPrefix "libusb" n)
            ((old.buildInputs or [ ]) ++ (old.propagatedBuildInputs or [ ]));
          propagatedBuildInputs = [ ];
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.buildPackages.xxd ];
          # sysfs / tree-mode read /sys + <linux/limits.h> → Linux-only. Off on
          # darwin (no /sys → no `lsusb -t`, no sysfs string fallback, and no
          # usbreset — portable.patch gates it behind with_sysfs). Names still
          # resolve everywhere via the embedded usb.ids.
          mesonFlags = (old.mesonFlags or [ ]) ++ [
            "-Dwith_sysfs=${pkgs.lib.boolToString pkgs.stdenv.hostPlatform.isLinux}"
            "-Dwith_tree_mode=${pkgs.lib.boolToString pkgs.stdenv.hostPlatform.isLinux}"
          ];
          doCheck = false;
          postPatch = (old.postPatch or "") + ''
            # Real usb.ids text parser (embed-backed) + bake hwdata's usb.ids in.
            cp ${./names.c} names.c
            xxd -i -n unpin_usb_ids \
              ${pkgs.buildPackages.hwdata}/share/hwdata/usb.ids > usb_ids.h
            # Always take the names.c (embed) branch + define HAVE_UDEV (which
            # gates names_init()/names_exit() in lsusb.c). names.c is the embed
            # parser, not the udev backend, so libudev is never linked.
            substituteInPlace meson.build \
              --replace "if get_option('with_udev') and libudev.found()" "if true"
          '';
          # One binary each (lsusb, usbhid-dump); drop scripts + man1.
          postInstall = ''
            rm -f $out/bin/usb-devices $out/bin/lsusb.py $out/bin/usbreset
            rm -rf $out/share/man/man1
          '';
        });

      windowsBuild = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; usbutils = (ulib.mingwStaticCross pkgs).usbutils; };
    };
}
