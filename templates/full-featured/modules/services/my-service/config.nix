{
  config,
  lib,
  pkgs,
  ...
}:

with lib;
{
  config = mkIf config.services.my-service.enable {
    # Create user and group
    users.users.${config.services.my-service.user} =
      mkIf (config.services.my-service.user == "myservice")
        {
          isSystemUser = true;
          group = config.services.my-service.group;
          description = "My Service daemon user";
        };

    users.groups.${config.services.my-service.group} = mkIf (
      config.services.my-service.group == "myservice"
    ) { };

    # Systemd service configuration
    systemd.services.my-service = {
      description = "My Custom Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${config.services.my-service.package}/bin/hello";
        User = config.services.my-service.user;
        Group = config.services.my-service.group;
        Restart = "on-failure";
        RestartSec = 5;

        # Security settings
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;

        # Environment variables
        Environment = mapAttrsToList (k: v: "${k}=${v}") config.services.my-service.environment;
      };

      # Add port to environment
      environment.PORT = toString config.services.my-service.port;
    };

    # Firewall configuration
    networking.firewall.allowedTCPPorts = mkIf config.services.my-service.openFirewall [
      config.services.my-service.port
    ];

    # Add the service package to system packages
    environment.systemPackages = [ config.services.my-service.package ];
  };
}
