# To build, use:
# nix-build nixos -I nixos-config=nixos/modules/installer/sd-card/sd-image-raspberrypi5.nix -A config.system.build.sdImage
{ config, lib, pkgs, ... }:

{
  imports = [
    ../../profiles/base.nix
    ./sd-image.nix
  ];

  boot.loader.grub.enable = false;
  boot.loader.raspberryPi.enable = true;
  boot.loader.raspberryPi.version = 5;
  boot.kernelPackages = pkgs.linuxPackages_rpi5;

  boot.consoleLogLevel = lib.mkDefault 7;

  # The serial ports listed here are:
  # - ttyS0: for Tegra (Jetson TX1)
  # - ttyAMA0: for QEMU's -machine virt
  boot.kernelParams = ["console=ttyS0,115200n8" "console=ttyAMA0,115200n8" "console=tty0"];

  sdImage = {
    firmwareSize = 1024;
    firmwarePartitionName = "NIXOS_BOOT";
    populateFirmwareCommands = "${config.system.build.installBootLoader} ${config.system.build.toplevel} -d ./firmware";
    populateRootCommands = "";
  };

  fileSystems."/boot/firmware" = {
    mountPoint = "/boot";
    neededForBoot = true;
  };
}
