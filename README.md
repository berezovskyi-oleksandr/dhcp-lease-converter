# DHCP Lease Converter

A POSIX shell script that converts DHCP lease files from dhcpcd format to dnsmasq format, enabling hostname visibility in OpenWrt dashboards when using dhcpcd-based DHCP servers (such as OPNsense).

## Why This Tool Exists

This tool solves a common networking scenario where you have:
- **A dhcpcd-based DHCP server** (such as OPNsense, pfSense, or other BSD-based firewalls)
- **OpenWrt-based WiFi access points** that need to display client hostnames in their dashboards

By default, OpenWrt expects lease information in dnsmasq format at `/tmp/dhcp.leases`. When your DHCP server is external and uses dhcpcd (like OPNsense), OpenWrt can't display meaningful hostnames for connected clients - they just show as qurstion mark.

This script bridges that gap by converting dhcpcd lease files to the dnsmasq format that OpenWrt expects, allowing you to see real hostnames in your OpenWrt management interface.

## How It Works

The script processes dhcpcd lease files and configuration files to generate dnsmasq-compatible lease entries. It handles:
- Dynamic leases from dhcpcd lease files
- Static reservations from dhcpd configuration files
- Proper timestamp conversion and formatting

## Features

- Convert dhcpcd dynamic leases to dnsmasq format
- Process static host reservations from dhcpd config files
- Handle duplicate MAC addresses (static leases preferred, latest dynamic lease wins)
- Time zone offset support for timestamp adjustment
- Verbose mode for debugging
- POSIX shell compatible (works with busybox sh)
- Proper error handling and validation

## Example Files

The `examples/` directory contains sample files that demonstrate all functionality:

- **`examples/dhcpcd.lease.example`** - Example dhcpcd lease file with dynamic leases
- **`examples/dhcpcd.config.example`** - Example dhcpcd config file with static leases  
- **`examples/dnsmasq.lease.example`** - Example dnsmasq format output

## Output Format

The script outputs [dnsmasq lease file format](https://deepwiki.com/imp/dnsmasq/4.3-lease-management#reading-leases). Static leases use timestamp 2147483647 (far future), dynamic leases use converted end timestamps, and missing fields are replaced with "*".

## Usage Examples

### Convert dynamic leases only:
```bash
./dhcp-lease-converter.sh -i examples/dhcpcd.lease.example
```

### Convert static leases only:
```bash
./dhcp-lease-converter.sh -c examples/dhcpcd.config.example
```

### Convert both dynamic and static leases:
```bash
./dhcp-lease-converter.sh -i examples/dhcpcd.lease.example -c examples/dhcpcd.config.example
```

### With verbose output:
```bash
./dhcp-lease-converter.sh -v -i examples/dhcpcd.lease.example -c examples/dhcpcd.config.example
```

### With time offset (e.g., +2 hours for timezone adjustment):
```bash
./dhcp-lease-converter.sh -t +2 -i examples/dhcpcd.lease.example -c examples/dhcpcd.config.example
```
**Note:** dhcpcd always uses UTC timestamps regardless of device timezone, while dnsmasq lease files expect timestamps in the device's local timezone. Use the time offset to convert from UTC to your OpenWrt device's timezone so lease expiration times display correctly in OpenWrt dashboards.

### Save to file:
```bash
./dhcp-lease-converter.sh -i examples/dhcpcd.lease.example -c examples/dhcpcd.config.example -o output.txt
```

## Installation

1. **Download the script**:
   ```bash
   wget https://raw.githubusercontent.com/berezovskyi-oleksandr/dhcp-lease-converter/master/dhcp-lease-converter.sh
   chmod +x dhcp-lease-converter.sh
   ```

2. **Or clone the repository**:
   ```bash
   git clone https://github.com/berezovskyi-oleksandr/dhcp-lease-converter.git
   cd dhcp-lease-converter
   chmod +x dhcp-lease-converter.sh
   ```

## Integration with OPNsense and OpenWRT

For a complete guide on integrating this tool with OPNsense DHCP server and OpenWRT access points, see [INTEGRATION.md](INTEGRATION.md). This guide includes:
- Step-by-step OPNsense setup with cron jobs
- OpenWRT configuration for automatic lease updates
- Troubleshooting tips

## Requirements

- POSIX-compatible shell (bash, dash, busybox sh)
- Standard Unix utilities: `sed`, `grep`, `date`, `mktemp`
- Works on OpenWrt, OPNsense, and most Linux distributions

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE.md) file for details.