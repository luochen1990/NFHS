{
  config,
  lib,
  pkgs,
  modulesPath,
  utils,
  ...
}:

{
  imports = [
    # Modules will be automatically discovered and imported from nixosModules/
    # The my-service module will be available here
  ];

  # Enable the custom service with custom configuration
  tweaks.enable = true;

  boot.loader.systemd-boot.enable = true;
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # Networking configuration
  networking.hostName = "laptop";
  networking.networkmanager.enable = true;

  # Enable SSH
  services.openssh.enable = true;
  services.openssh.settings = {
    PermitRootLogin = "no";
    PasswordAuthentication = false;
  };

  # Create a demo user
  users.users.demo = {
    isNormalUser = true;
    description = "Demo user";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    openssh.authorizedKeys.keys = [
      # Add your SSH public keys here
      # "ssh-rsa AAAAB3NzaC1yc2EAAAA..."
    ];
  };

  # Create a welcome message
  users.motd = ''
    Welcome to FlakeFHS Example!

    This system is configured using Flake FHS.
  '';

  system.stateVersion = "25.11";
}
