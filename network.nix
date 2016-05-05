let
  gce-credentials = {
    project = "adjective-noun-digits";
    serviceAccount = "[many digits]-compute@developer.gserviceaccount.com";
    accessKey = "./key.pem";
  };

  openvpn = {
    ca = ./vpn/ca.crt;
    cert = ./vpn/server.crt;
    key = ./vpn/server.key;
    ta = ./vpn/ta.key;
    dh = ./vpn/dh2048.pem;

    client_subnet = "10.89.98.0";
    client_mask_bits = 24;
    client_mask = "255.255.255.0";

    forward_to_subnet = "192.168.4.0";
    forward_to_mask_bits = 24;
    forward_to_mask = "255.255.255.0";

    dns_server = "169.254.169.254";
  };

in
rec {

  my-vpn = { resources, ...}:  {

    deployment.targetEnv = "gce";
    deployment.gce = gce-credentials // {
      region = "us-central1-a";
      tags = [ "public-vpn" ];
      network = resources.gceNetworks.lb-net;
    };


    networking.firewall.allowedUDPPorts = [ 1194 ];
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

    services.openvpn.servers.example = {
      autoStart = true;

      up = ''
        iptables -I FORWARD -i tun0 -o eth0 \
            -s ${openvpn.client_subnet}/${toString openvpn.client_mask_bits} \
            -d ${openvpn.forward_to_subnet}/${toString openvpn.forward_to_mask_bits} \
            -m conntrack --ctstate NEW -j ACCEPT

        iptables -I FORWARD -m conntrack \
            --ctstate RELATED,ESTABLISHED -j ACCEPT
        iptables -I POSTROUTING -t nat -o eth0 \
            -s ${openvpn.client_subnet}/${toString openvpn.client_mask_bits} \
            -j MASQUERADE
      '';

      down = ''
        iptables -D FORWARD -i tun0 -o eth0 \
            -s ${openvpn.client_subnet}/${toString openvpn.client_mask_bits} \
            -d ${openvpn.forward_to_subnet}/${toString openvpn.forward_to_mask_bits} \
            -m conntrack --ctstate NEW -j ACCEPT

        iptables -D FORWARD -m conntrack \
            --ctstate RELATED,ESTABLISHED -j ACCEPT
        iptables -D POSTROUTING -t nat -o eth0 \
            -s ${openvpn.client_subnet}/${toString openvpn.client_mask_bits} \
            -j MASQUERADE

      '';

      config = ''
        port 1194
        proto udp
        dev tun
        ca ${openvpn.ca}
        cert ${openvpn.cert}
        key ${openvpn.key}
        dh ${openvpn.dh}
        tls-auth ${openvpn.ta} 0

        server ${openvpn.client_subnet} ${openvpn.client_mask}
        keepalive 10 120
        comp-lzo
        max-clients 5
        user nobody
        group nogroup
        persist-key
        persist-tun
        verb 6
        reneg-sec 0

        push "route ${openvpn.forward_to_subnet} ${openvpn.forward_to_mask}"
        push "redirect-gateway def1" # https://openvpn.net/index.php/open-source/documentation/howto.html#redirect
      '';
    };

  };

  # use nixos-unstable image
  # this specification is identical to the default one and can omitted
  resources.gceImages.bootstrap = gce-credentials // {
    sourceUri = "gs://nixos-cloud-images/nixos-15.09.425.7870f20-x86_64-linux.raw.tar.gz";
  };

  # create a network that allows SSH traffic(by default), pings
  # and HTTP traffic for machines tagged "public-http"
  resources.gceNetworks.lb-net = gce-credentials // {
    addressRange = "192.168.4.0/24";
    firewall = {
      allow-openvpn = {
        targetTags = [ "public-vpn" ];
        allowed.udp = [ 1194 ];
      };

      allow-ping.allowed.icmp = null;
    };
  };
}
