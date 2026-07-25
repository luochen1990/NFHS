{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.services.web-server;
  webRoot = pkgs.writeTextDir "index.html" cfg.content;
in
{
  # This config is only applied if services.web-server.enable is true

  systemd.services.web-server = {
    description = "Simple Web Server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];

    serviceConfig = {
      DynamicUser = true;
      ExecStart = "${pkgs.python3}/bin/python3 -m http.server ${toString cfg.port} --directory ${webRoot}";
      Restart = "always";
    };
  };

  networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];
}
