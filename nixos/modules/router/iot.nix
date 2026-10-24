{ pkgs, routerConst, ... }:
let
  inherit (routerConst)
    wanIf
    iotLanIf
    iotVlanIf
    iotWifiIf
    lanDhcpServerConfig
    ;
  passwordFile = "/var/lib/hostapd/iot-password";
in
{
  systemd.network = {
    netdevs = {
      "20-iot-bridge".netdevConfig = {
        Name = iotLanIf;
        Kind = "bridge";
      };
      "20-iot-vlan" = {
        netdevConfig = {
          Name = iotVlanIf;
          Kind = "vlan";
        };
        vlanConfig.Id = 40;
      };
    };
    networks = {
      "20-iot-vlan" = {
        matchConfig.Name = iotVlanIf;
        networkConfig = {
          Bridge = iotLanIf;
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        };
      };
      "20-iot-wifi" = {
        matchConfig.Name = iotWifiIf;
        networkConfig = {
          Bridge = iotLanIf;
          LinkLocalAddressing = "no";
          IPv6AcceptRA = false;
        };
      };
      "21-iot-bridge" = {
        matchConfig.Name = iotLanIf;
        networkConfig = {
          Address = "172.16.4.1/24";
          ConfigureWithoutCarrier = true;
          DHCPServer = true;
          IPv6AcceptRA = false;
          IPv6SendRA = true;
          DHCPPrefixDelegation = true;
          IPv4Forwarding = true;
          IPv6Forwarding = true;
        };
        dhcpServerConfig = lanDhcpServerConfig "172.16.4.1";
        extraConfig = ''
          [IPv6SendRA]
          RouterLifetimeSec=1800
          EmitDNS=yes
          DNS=_link_local

          [DHCPPrefixDelegation]
          UplinkInterface=${wanIf}
          SubnetId=4
          Announce=yes
          Assign=yes
          Token=eui64
        '';
      };
    };
  };

  systemd.services.iot-wifi-password = {
    description = "Create the IoT WLAN password";
    before = [ "hostapd.service" ];
    requiredBy = [ "hostapd.service" ];
    path = [ pkgs.openssl ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "hostapd";
      StateDirectoryMode = "0700";
      UMask = "0077";
    };
    script = ''
      if [ ! -s ${passwordFile} ]; then
        openssl rand -hex 16 > ${passwordFile}
      fi
    '';
  };

  services.hostapd = {
    enable = true;
    radios.${iotWifiIf} = {
      countryCode = "JP";
      band = "2g";
      channel = 6;
      wifi4.enable = true;
      networks.${iotWifiIf} = {
        ssid = "WLAN-212355-2G";
        authentication = {
          mode = "wpa2-sha1";
          wpaPasswordFile = passwordFile;
        };
        settings.bridge = iotLanIf;
      };
    };
  };
}
