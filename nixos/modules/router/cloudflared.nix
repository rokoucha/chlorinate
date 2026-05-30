{ pkgs, ... }:
{
  services.cloudflared = {
    enable = true;
    tunnels = {
      "54c4d022-c007-4ca3-943e-8b7bc57e70d4" = {
        credentialsFile = "/var/lib/cloudflared/54c4d022-c007-4ca3-943e-8b7bc57e70d4.json";
        default = "http_status:404";
        ingress = {
          "chlorinate.ggrel.net" = {
            service = "ssh://localhost:22";
          };
        };
      };
    };
  };

  environment.systemPackages = [ pkgs.cloudflared ];
}
