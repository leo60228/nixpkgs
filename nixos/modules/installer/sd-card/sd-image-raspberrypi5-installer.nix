{
  imports = [
    ../../profiles/installation-device.nix
    ./sd-image-raspberrypi5.nix
  ];
  disabledModules = [ "profiles/all-hardware.nix" ]; # broken on linux-rpi

  # the installation media is also the installation target,
  # so we don't want to provide the installation configuration.nix.
  installer.cloneConfig = false;
}
