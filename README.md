# pve-technitium-dns

A [Technitium DNS Server](https://technitium.com/dns/) plugin for Proxmox VE's SDN stack. Enables automatic DNS record creation and deletion in Technitium when containers and VMs are assigned DHCP leases via PVE's built-in SDN DHCP. Adds Technitium as a native DNS provider alongside PowerDNS in the PVE web UI.

## Requirements

- Proxmox VE 9.x (tested on 9.1.11)
- Technitium DNS Server (tested on v15.x)
- A Technitium API token with permission to manage your DNS zone

## How It Works

PVE's SDN stack manages DHCP leases for containers and VMs on SDN vnets. When a lease is assigned or released, PVE calls the configured DNS plugin to add or remove the corresponding A/AAAA and PTR records. This plugin implements that interface for Technitium's HTTP API.

## Installation

> **Note:** These files are part of PVE packages managed by `apt`. Updates to `libpve-network-perl` or `pve-manager` will overwrite your changes. Re-run the install script after updates to those packages.

### 1. Copy the Perl plugin

```bash
cp perl/PVE/Network/SDN/Dns/TechnitiumPlugin.pm /usr/share/perl5/PVE/Network/SDN/Dns/
```

### 2. Register the plugin

Add the following two lines to `/usr/share/perl5/PVE/Network/SDN/Dns.pm` after the existing PowerDNS lines:

```perl
use PVE::Network::SDN::Dns::TechnitiumPlugin;
PVE::Network::SDN::Dns::TechnitiumPlugin->register();
```

Add the following line to `/usr/share/perl5/PVE/API2/Network/SDN/Dns.pm` after the PowerDNS import:

```perl
use PVE::Network::SDN::Dns::TechnitiumPlugin;
```

### 3. Install the UI panel

Copy `js/TechnitiumEdit.js` to `/usr/share/pve-manager/www/manager6/sdn/dns/`

Then add the following entry to the `sdndnsSchema` object in `/usr/share/pve-manager/www/manager6/Utils.js`:

```javascript
technitium: {
    name: 'technitium',
    ipanel: 'TechnitiumInputPanel',
    faIcon: 'th',
},
```

Then rebuild the combined JS (or use the install script below which patches the pre-built `pvemanagerlib.js` directly).

### 4. Restart PVE services

```bash
systemctl restart pvedaemon pveproxy
```

### Automated Install

```bash
sudo bash install/install.sh
```

## Configuration

1. In Technitium, create an API token under **Administration → Sessions → Create Token**
2. In PVE, go to **Datacenter → SDN → DNS → Add → Technitium**
3. Set:
   - **ID**: a short identifier (e.g. `technitium`)
   - **Server URL**: full URL to your Technitium instance (e.g. `http://ns.internal:5380`)
   - **API Token**: the token from step 1
   - **TTL**: optional, defaults to 3600
4. Edit your SDN zone and set the **DNS** field to the ID from step 3
5. Set the **DNS Zone** to match your authoritative zone in Technitium (e.g. `home`)

## Caveats

- Reverse DNS (PTR records) requires the corresponding reverse zone to exist in Technitium. If you don't need reverse DNS, disable it in the SDN zone options.
- The plugin uses unique property names (`server`, `apitoken`) to avoid conflicts with the PowerDNS plugin's schema registration.
- This plugin modifies PVE system files. It is not affiliated with or endorsed by Proxmox or Technitium.

## Contributing

Patches welcome. If you want to submit this upstream to Proxmox, see the [Proxmox developer documentation](https://pve.proxmox.com/wiki/Developer_Documentation) — patches go to the `pve-devel` mailing list as `git format-patch` output.

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE)
