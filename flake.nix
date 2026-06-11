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
      smoke = [ "--version" ];
      # `usbutils --version` dispatches to lsusb (defaultApplet) -> "lsusb
      # (usbutils) 019"; match the suite name.
      smokePattern = "usbutils";

      build = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; usbutils = pkgs.pkgsStatic.usbutils; };

      windowsBuild = pkgs:
        import ./multicall.nix { lib = pkgs.lib // ulib; }
          { inherit pkgs; usbutils = (ulib.mingwStaticCross pkgs).usbutils; };
    };
}
