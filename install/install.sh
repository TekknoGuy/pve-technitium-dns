#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

PVE_PERL="/usr/share/perl5/PVE"
PVE_JS="/usr/share/pve-manager/www/manager6"

# Minimum tested PVE version
MIN_VERSION="9.1"

echo "Installing pve-technitium-dns..."

# Check we're on a PVE host
if ! command -v pveversion &>/dev/null; then
    echo "ERROR: This doesn't appear to be a Proxmox VE host."
    exit 1
fi

# Check running as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root."
    exit 1
fi

PVE_VERSION=$(pveversion | grep -oP 'pve-manager/\K[0-9]+\.[0-9]+')
echo "Detected PVE version: $PVE_VERSION"
echo "Tested against: $MIN_VERSION.x"
echo ""
echo "If your version differs significantly, review the patch targets manually before proceeding."
echo ""

# Helper: check an anchor string exists in a file before patching
check_anchor() {
    local file="$1"
    local pattern="$2"
    if ! grep -q "$pattern" "$file"; then
        echo "ERROR: Expected pattern not found in $file:"
        echo "  $pattern"
        echo ""
        echo "The file may have changed between PVE versions. Manual installation required."
        echo "See README.md for instructions."
        exit 1
    fi
}

echo "Backing up modified PVE files..."
cp "$PVE_PERL/Network/SDN/Dns.pm"      "$PVE_PERL/Network/SDN/Dns.pm.bak"
cp "$PVE_PERL/API2/Network/SDN/Dns.pm" "$PVE_PERL/API2/Network/SDN/Dns.pm.bak"
cp "$PVE_JS/Utils.js"                   "$PVE_JS/Utils.js.bak"

echo "Installing Perl plugin..."
cp "$REPO_DIR/perl/PVE/Network/SDN/Dns/TechnitiumPlugin.pm" \
   "$PVE_PERL/Network/SDN/Dns/TechnitiumPlugin.pm"

echo "Registering plugin in Dns.pm..."
if ! grep -q 'TechnitiumPlugin' "$PVE_PERL/Network/SDN/Dns.pm"; then
    check_anchor "$PVE_PERL/Network/SDN/Dns.pm" "use PVE::Network::SDN::Dns::PowerdnsPlugin;"
    check_anchor "$PVE_PERL/Network/SDN/Dns.pm" "PowerdnsPlugin->register();"
    sed -i '/use PVE::Network::SDN::Dns::PowerdnsPlugin;/a use PVE::Network::SDN::Dns::TechnitiumPlugin;' \
        "$PVE_PERL/Network/SDN/Dns.pm"
    sed -i '/PVE::Network::SDN::Dns::PowerdnsPlugin->register();/a PVE::Network::SDN::Dns::TechnitiumPlugin->register();' \
        "$PVE_PERL/Network/SDN/Dns.pm"
else
    echo "  Already registered in Dns.pm, skipping."
fi

echo "Registering plugin in API2/Dns.pm..."
if ! grep -q 'TechnitiumPlugin' "$PVE_PERL/API2/Network/SDN/Dns.pm"; then
    # Try the standard anchor first
    if grep -q 'use PVE::Network::SDN::Dns::PowerdnsPlugin;' "$PVE_PERL/API2/Network/SDN/Dns.pm"; then
        sed -i '/use PVE::Network::SDN::Dns::PowerdnsPlugin;/a use PVE::Network::SDN::Dns::TechnitiumPlugin;' \
            "$PVE_PERL/API2/Network/SDN/Dns.pm"
    # Fall back to inserting after the Dns module import
    elif grep -q 'use PVE::Network::SDN::Dns;' "$PVE_PERL/API2/Network/SDN/Dns.pm"; then
        sed -i '/use PVE::Network::SDN::Dns;/a use PVE::Network::SDN::Dns::TechnitiumPlugin;' \
            "$PVE_PERL/API2/Network/SDN/Dns.pm"
    else
        echo "ERROR: Could not find a suitable anchor in API2/Network/SDN/Dns.pm."
        echo "Manual installation required. See README.md."
        exit 1
    fi
else
    echo "  Already registered in API2/Dns.pm, skipping."
fi

echo "Installing UI panel..."
cp "$REPO_DIR/js/TechnitiumEdit.js" "$PVE_JS/sdn/dns/TechnitiumEdit.js"

echo "Registering plugin in Utils.js..."
if ! grep -q 'technitium:' "$PVE_JS/Utils.js"; then
    check_anchor "$PVE_JS/Utils.js" "powerdns:"
    sed -i 's/            powerdns: {/            technitium: {\n                name: '"'"'technitium'"'"',\n                ipanel: '"'"'TechnitiumInputPanel'"'"',\n                faIcon: '"'"'th'"'"',\n            },\n            powerdns: {/' \
        "$PVE_JS/Utils.js"
else
    echo "  Already registered in Utils.js, skipping."
fi

echo "Verifying Perl module loads cleanly..."
if ! perl -e 'use PVE::Network::SDN::Dns;' 2>&1; then
    echo "ERROR: Perl module failed to load. Restoring backups..."
    cp "$PVE_PERL/Network/SDN/Dns.pm.bak"      "$PVE_PERL/Network/SDN/Dns.pm"
    cp "$PVE_PERL/API2/Network/SDN/Dns.pm.bak" "$PVE_PERL/API2/Network/SDN/Dns.pm"
    exit 1
fi

echo "Restarting PVE services..."
systemctl restart pvedaemon pveproxy

echo ""
echo "Done. Technitium DNS plugin installed successfully."
echo "Go to Datacenter -> SDN -> DNS -> Add -> Technitium to configure."
echo ""
echo "NOTE: Updates to libpve-network-perl or pve-manager will overwrite these changes."
echo "Re-run this script after updating those packages."
