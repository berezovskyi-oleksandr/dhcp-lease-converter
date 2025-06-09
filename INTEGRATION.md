# DHCP Lease Integration: OPNsense to OpenWRT

## Overview

Simple integration to enable hostname visibility in OpenWRT dashboards when using OPNsense as DHCP server.

For installation instructions and general tool usage, see [README.md](README.md).

**Warning:** This is a basic integration guide that doesn't include error handling, retries, authentication, or other security considerations. Use at your own risk and adapt to your security requirements.

## OPNsense Setup

### 1. Install Script

```bash
cp dhcp-lease-converter.sh /usr/local/bin/
chmod +x /usr/local/bin/dhcp-lease-converter.sh
```

### 2. Create OPNsense Action

Create `/usr/local/opnsense/service/conf/actions.d/actions_dhcpsync.conf`:

```ini
[sync]
command:/usr/local/bin/dhcp-lease-converter.sh -i /var/dhcpd/var/db/dhcpd.leases -c /var/dhcpd/etc/dhcpd.conf -o /usr/local/www/dhcp.leases
type:script
message:Syncing DHCP leases
description:DHCP lease sync to dnsmasq format
```

### 3. Restart Services

```bash
service configd restart
```

### 4. Add Cron Job

Go to `System > Settings > Cron` and add the following job:
| Field | Value |
|-------|-------|
| Minutes | */5 |
| Hours | * |
| Day of Month | * |
| Month | * |
| Day of Week | * |
| Command | DHCP lease sync to dnsmasq format |
| Description | Create dhcp.leases file for OpenWRT APs |

That's it for OPNsense. The file will be available at `http://opnsense-ip/dhcp.leases`.

## OpenWRT Setup

### 1. Add Cron Job
#### Via Web UI

On each OpenWRT AP go to `System > Scheduled Tasks` and add the following cron job:

```
# Replace 192.168.1.1 with your OPNsense IP/hostname
*/2 * * * * wget -q --no-check-certificate -O /tmp/dhcp.leases https://192.168.1.1/dhcp.leases
```

#### Via Command Line

```bash
# Replace 192.168.1.1 with your OPNsense IP/hostname
echo "*/2 * * * * wget -q --no-check-certificate -O /tmp/dhcp.leases https://192.168.1.1/dhcp.leases" >> /etc/crontabs/root
/etc/init.d/cron restart
```

Done. Hostnames should appear in your OpenWRT dashboard.

## Notes

- **Timezone**: If timestamps look wrong, add `-t +2` (or appropriate offset) to the dhcp-lease-converter.sh command
- **Testing**: Run the commands manually first to verify they work
- **Logs**: 
  - For OPNsense check via `GUI System > Log Files > Backend` and search for "Syncing DHCP leases"
  - For OpenWRT use `logread -e cron` if something doesn't work
