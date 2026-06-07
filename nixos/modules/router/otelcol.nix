{ otelcol, routerConst, pkgs, ... }:
let
  inherit (routerConst) mapeBrV6;
  blackboxAddr = "127.0.0.1:9115";

  blackboxRelabel = [
    { source_labels = [ "__address__" ]; target_label = "__param_target"; }
    { source_labels = [ "__param_target" ]; target_label = "instance"; }
    { target_label = "__address__"; replacement = blackboxAddr; }
  ];

  mkJob = { name, module, targets }: {
    job_name = name;
    metrics_path = "/probe";
    params.module = [ module ];
    static_configs = [{ inherit targets; }];
    relabel_configs = blackboxRelabel;
  };
in
{
  services.opentelemetry-collector = {
    enable = true;
    package = otelcol;
    settings = {
      "receivers"."prometheus/self".config.scrape_configs = [
        {
          job_name = "opentelemetry-collector";
          scrape_interval = "10s";
          static_configs = [{ targets = [ "0.0.0.0:8888" ]; }];
        }
      ];

      receivers.journald = {
        priority = "info";
      };

      receivers.prometheus.config = {
        global.scrape_interval = "30s";
        scrape_configs = [
        (mkJob { name = "ping_v4_mape";   module = "icmp_v4";        targets = [ "1.1.1.1" "8.8.8.8" ]; })
        (mkJob { name = "ping_v4_itscom"; module = "icmp_v4_itscom"; targets = [ "1.1.1.1" "8.8.8.8" ]; })
        (mkJob { name = "ping_v6";        module = "icmp_v6";        targets = [ "2606:4700:4700::1111" "2001:4860:4860::8888" ]; })
        (mkJob { name = "ping_mape_br";   module = "icmp_v6_br";     targets = [ mapeBrV6 ]; })
        (mkJob { name = "http_v6_flets";  module = "http_v6";        targets = [ "http://www1.speed-test.flets-east.jp" ]; })
        {
          job_name = "node";
          scrape_interval = "30s";
          static_configs = [{ targets = [ "127.0.0.1:9100" ]; }];
        }
        ];
      };

      processors = {
        memory_limiter = {
          check_interval = "1s";
          limit_mib = 256;
          spike_limit_mib = 64;
        };
        resourcedetection = {
          detectors = [ "system" ];
        };
        resource = {
          attributes = [{
            key = "service.name";
            value = "chlorinate";
            action = "upsert";
          }];
        };
        batch = { };
      };

      exporters.otlphttp = {
        endpoint = "https://otel.ggrel.net";
        headers.Authorization = "Bearer \${env:OTLP_TOKEN}";
      };

      service.pipelines.metrics = {
        receivers = [ "prometheus" "prometheus/self" ];
        processors = [ "memory_limiter" "resourcedetection" "resource" "batch" ];
        exporters = [ "otlphttp" ];
      };

      service.pipelines.logs = {
        receivers = [ "journald" ];
        processors = [ "memory_limiter" "resourcedetection" "resource" "batch" ];
        exporters = [ "otlphttp" ];
      };
    };
  };

  systemd.services.opentelemetry-collector.serviceConfig = {
    EnvironmentFile = "/var/lib/otelcol/env";
    # journald receiver shells out to journalctl.
    Path = [ "${pkgs.systemd}/bin" ];
  };

}
