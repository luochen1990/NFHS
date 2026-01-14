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
    # Modules will be automatically discovered and imported from modules/
    # The my-service module will be available here
  ];

  # Enable the custom service with custom configuration
  services.my-service = {
    enable = true;
    port = 9090;
    openFirewall = true;
    environment = {
      LOG_LEVEL = "debug";
      DATA_DIR = "/var/lib/myservice";
    };
  };

  # Basic system configuration
  boot.loader.systemd-boot.enable = true;
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  # System packages from our flake
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget

    # Include packages from our flake (if they exist)
    # utils.packages.hello-fhs or similar would be available here
  ];

  # Networking configuration
  networking.hostName = "NFHS-example";
  networking.networkmanager.enable = true;

  # Firewall configuration
  networking.firewall.enable = true;

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
    Welcome to NFHS Example!

    This system is configured using NFHS with:
    - Custom service on port ${toString config.services.my-service.port}
    - Development tools and utilities
    - Security hardening

    Run 'nix run .#status' to see available apps and services.
  '';

  system.stateVersion = "24.11";
}
