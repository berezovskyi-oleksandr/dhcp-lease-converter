#!/bin/sh

readonly FAR_FUTURE_TIMESTAMP=2147483647
readonly SECONDS_PER_HOUR=3600
readonly UNKNOWN_FIELD="*"

lease_file=""
config_file=""
output_file="-"
time_offset=0
verbose=0

# Temporary files for associative array simulation
LEASE_DATA_FILE=$(mktemp)
LEASE_STARTS_FILE=$(mktemp)

# Cleanup function
cleanup() {
    rm -f "$LEASE_DATA_FILE" "$LEASE_STARTS_FILE"
}

# Set up cleanup on exit
trap cleanup EXIT INT TERM

# Initialize temporary files
true > "$LEASE_DATA_FILE"
true > "$LEASE_STARTS_FILE"

# Utility functions
extract_field() {
    line="$1"
    pattern="$2"
    echo "$line" | sed -nr "s/.*$pattern.*/\1/p"
}

log_verbose() {
    if [ "$verbose" -eq 1 ]; then
        echo "[DEBUG] $*" >&2
    fi
}

# Convert dhcpcd date format (YYYY/MM/DD HH:MM:SS) to unix timestamp
date_to_timestamp() {
    date_str="$1"
    
    # Try BSD date format first (OPNsense/FreeBSD)
    if command -v date >/dev/null 2>&1 && date -j -f "%Y/%m/%d %H:%M:%S" "$date_str" +%s 2>/dev/null; then
        return
    fi
    
    # Try busybox date with -D format
    formatted_date=$(echo "$date_str" | sed 's|/|-|g')
    if date -D "%Y-%m-%d %H:%M:%S" -d "$formatted_date" +%s 2>/dev/null; then
        return
    fi
    
    # Try GNU date with -d
    if date -d "$formatted_date" +%s 2>/dev/null; then
        return
    fi
    
    log_verbose "Warning: Could not parse date '$date_str', using timestamp 0"
    echo "0"
}

show_usage() {
    echo "Usage: $0 [--in-dhcpcd-lease FILE] [--in-dhcpcd-config FILE] [-o FILE] [--time-offset HOURS]" >&2
    echo "" >&2
    echo "Options:" >&2
    echo "  -i, --in-dhcpcd-lease FILE    Input dhcpcd lease file (use - for stdin)" >&2
    echo "  -c, --in-dhcpcd-config FILE   Input dhcpcd config file with static leases" >&2
    echo "" >&2
    echo "Note: At least one input file (-i or -c) must be provided" >&2
    echo "  -o, --output-lease FILE       Output file (use - for stdout, default: -)" >&2
    echo "  -t, --time-offset N           Hours to add/subtract from UTC time (e.g., -2, +3, default: 0)" >&2
    echo "  -v, --verbose                 Enable verbose/debug output" >&2
    echo "  -h, --help                    Show this help message" >&2
    exit 1
}

# Parse command line arguments
while [ $# -gt 0 ]; do
    case $1 in
        -i|--in-dhcpcd-lease)
            lease_file="$2"
            shift 2
            ;;
        -c|--in-dhcpcd-config)
            config_file="$2"
            shift 2
            ;;
        -o|--output-lease)
            output_file="$2"
            shift 2
            ;;
        -t|--time-offset)
            time_offset="$2"
            if ! echo "$time_offset" | grep -q '^[+-]\?[0-9]\+$'; then
                echo "Error: --time-offset must be a number (e.g., -2, +3)" >&2
                show_usage
            fi
            shift 2
            ;;
        -v|--verbose)
            verbose=1
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_usage
            ;;
    esac
done

# Helper functions for associative array simulation
set_lease_data() {
    mac="$1"
    data="$2"
    grep -v "^$mac|" "$LEASE_DATA_FILE" > "${LEASE_DATA_FILE}.tmp" 2>/dev/null || true
    echo "$mac|$data" >> "${LEASE_DATA_FILE}.tmp"
    mv "${LEASE_DATA_FILE}.tmp" "$LEASE_DATA_FILE"
}

get_lease_data() {
    mac="$1"
    grep "^$mac|" "$LEASE_DATA_FILE" | cut -d'|' -f2- | head -1
}

set_lease_start() {
    mac="$1"
    start="$2"
    grep -v "^$mac|" "$LEASE_STARTS_FILE" > "${LEASE_STARTS_FILE}.tmp" 2>/dev/null || true
    echo "$mac|$start" >> "${LEASE_STARTS_FILE}.tmp"
    mv "${LEASE_STARTS_FILE}.tmp" "$LEASE_STARTS_FILE"
}

get_lease_start() {
    mac="$1"
    grep "^$mac|" "$LEASE_STARTS_FILE" | cut -d'|' -f2 | head -1
}

# Parsing functions
process_config() {
    log_verbose "Processing config file for static leases"
    in_host=0
    mac=""
    ip=""
    hostname=""
    line_num=0
    
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        if echo "$line" | grep -q '^host[[:space:]]\+[^[:space:]]\+[[:space:]]*{'; then
            in_host=1
            log_verbose "Line $line_num: Found host block start"
            mac=""
            ip=""
            hostname=""
            continue
        fi
        
        if [ $in_host -eq 1 ]; then
            if [ -z "$mac" ]; then
                extracted_mac=$(echo "$line" | sed -nr 's/.*hardware[[:space:]]+ethernet[[:space:]]+([0-9a-fA-F:]+).*/\1/p')
                if [ -n "$extracted_mac" ]; then
                    mac="$extracted_mac"
                fi
            fi
            
            if [ -z "$ip" ]; then
                extracted_ip=$(echo "$line" | sed -nr 's/.*fixed-address[[:space:]]+([0-9.]+).*/\1/p')
                if [ -n "$extracted_ip" ]; then
                    ip="$extracted_ip"
                fi
            fi
            
            if [ -z "$hostname" ]; then
                extracted_hostname=$(echo "$line" | sed -nr 's/.*option[[:space:]]+host-name[[:space:]]+"([^"]+)".*/\1/p')
                if [ -n "$extracted_hostname" ]; then
                    hostname="$extracted_hostname"
                fi
            fi
            
            # Check if we're at the end of a host block
            if echo "$line" | grep -q '^}'; then
                in_host=0
                
                # Process the static lease if we have all required data
                if [ -n "$mac" ] && [ -n "$ip" ]; then
                    log_verbose "Line $line_num: Processing static lease MAC=$mac IP=$ip HOSTNAME=${hostname:-$UNKNOWN_FIELD}"
                    timestamp=$FAR_FUTURE_TIMESTAMP
                    
                    if [ "$time_offset" -ne 0 ]; then
                        timestamp=$((timestamp + (time_offset * SECONDS_PER_HOUR)))
                    fi
                    
                    if [ -z "$hostname" ]; then
                        hostname="$UNKNOWN_FIELD"
                    fi
                    
                    if [ -z "$(get_lease_data "$mac")" ]; then
                        set_lease_data "$mac" "2038/01/19 03:14:07|$ip|$hostname|"
                        set_lease_start "$mac" "$FAR_FUTURE_TIMESTAMP"
                        log_verbose "Line $line_num: Added static lease for $mac"
                    else
                        log_verbose "Line $line_num: Skipping duplicate static lease for $mac"
                    fi
                else
                    log_verbose "Line $line_num: Incomplete host block - missing MAC or IP (MAC='$mac', IP='$ip')"
                fi
            fi
        fi
    done
}

process_leases() {
    log_verbose "Processing dynamic leases"
    in_lease=0
    ip=""
    mac=""
    hostname=""
    client_id=""
    ends=""
    starts=""
    binding_state=""
    line_num=0
    
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        if echo "$line" | grep -q '^lease[[:space:]]\+[0-9.]\+[[:space:]]*{'; then
            in_lease=1
            ip=$(echo "$line" | sed -nr 's/^lease[[:space:]]+([0-9.]+)[[:space:]]*\{.*/\1/p')
            log_verbose "Line $line_num: Found lease block for IP $ip"
            mac=""
            hostname=""
            client_id=""
            ends=""
            starts=""
            binding_state=""
            continue
        fi
        
        if [ $in_lease -eq 1 ]; then
            if [ -z "$mac" ]; then
                extracted_mac=$(echo "$line" | sed -nr 's/.*hardware[[:space:]]+ethernet[[:space:]]+([0-9a-fA-F:]+).*/\1/p')
                if [ -n "$extracted_mac" ]; then
                    mac="$extracted_mac"
                fi
            fi
            
            if [ -z "$hostname" ]; then
                extracted_hostname=$(echo "$line" | sed -nr 's/.*client-hostname[[:space:]]+"([^"]+)".*/\1/p')
                if [ -n "$extracted_hostname" ]; then
                    hostname="$extracted_hostname"
                fi
            fi
            
            if echo "$line" | grep -q 'uid[[:space:]]\+".*"'; then
                client_id="01:$(echo "$mac" | sed 's/://g')"
            fi
            
            if [ -z "$starts" ]; then
                extracted_starts=$(echo "$line" | sed -nr 's/.*starts[[:space:]]+[0-9]+[[:space:]]+([0-9]{4}\/[0-9]{2}\/[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}).*/\1/p')
                if [ -n "$extracted_starts" ]; then
                    starts="$extracted_starts"
                fi
            fi
            
            if [ -z "$ends" ]; then
                extracted_ends=$(echo "$line" | sed -nr 's/.*ends[[:space:]]+[0-9]+[[:space:]]+([0-9]{4}\/[0-9]{2}\/[0-9]{2}[[:space:]]+[0-9]{2}:[0-9]{2}:[0-9]{2}).*/\1/p')
                if [ -n "$extracted_ends" ]; then
                    ends="$extracted_ends"
                fi
            fi
            
            if [ -z "$binding_state" ] && echo "$line" | grep -q 'binding[[:space:]]\+state[[:space:]]\+[a-z]\+'; then
                binding_state=$(echo "$line" | sed -nr 's/.*binding[[:space:]]+state[[:space:]]+([a-z]+).*/\1/p')
            fi
            
            if echo "$line" | grep -q '^}'; then
                in_lease=0
                
                if [ "$binding_state" = "active" ] && [ -n "$mac" ] && [ -n "$ip" ] && [ -n "$ends" ] && [ -n "$starts" ]; then
                    log_verbose "Line $line_num: Processing active lease MAC=$mac IP=$ip HOSTNAME=${hostname:-$UNKNOWN_FIELD}"
                    start_timestamp=$(date_to_timestamp "$starts")
                    
                    if [ "$start_timestamp" -eq 0 ]; then
                        log_verbose "Line $line_num: Warning - failed to parse start time '$starts' for lease $mac/$ip"
                    fi
                    
                    existing_start=$(get_lease_start "$mac")
                    if [ -n "$existing_start" ]; then
                        if [ "$existing_start" -eq $FAR_FUTURE_TIMESTAMP ]; then
                            continue
                        fi
                        if [ "$start_timestamp" -gt "$existing_start" ]; then
                            set_lease_start "$mac" "$start_timestamp"
                            set_lease_data "$mac" "$ends|$ip|${hostname:-$UNKNOWN_FIELD}|${client_id}"
                        fi
                    else
                        set_lease_start "$mac" "$start_timestamp"
                        set_lease_data "$mac" "$ends|$ip|${hostname:-$UNKNOWN_FIELD}|${client_id}"
                    fi
                fi
            fi
        fi
    done
}

# Output functions
output_leases() {
    while IFS='|' read -r mac data; do
        if [ -n "$mac" ] && [ -n "$data" ]; then
            IFS='|' read -r ends ip hostname client_id <<EOF
$data
EOF
            
            timestamp=""
            timestamp=$(date_to_timestamp "$ends")
            
            if [ "$timestamp" -eq 0 ]; then
                log_verbose "Warning - failed to parse end time '$ends' for lease $mac/$ip, using timestamp 0"
            fi
            
            if [ "$time_offset" -ne 0 ]; then
                timestamp=$((timestamp + (time_offset * SECONDS_PER_HOUR)))
            fi
            
            if [ -n "$client_id" ]; then
                echo "$timestamp $mac $ip $hostname $client_id"
            else
                echo "$timestamp $mac $ip $hostname $UNKNOWN_FIELD"
            fi
        fi
    done < "$LEASE_DATA_FILE" | sort -n
}

main() {
    if [ -z "$lease_file" ] && [ -z "$config_file" ]; then
        echo "Error: At least one input file (-i or -c) must be provided" >&2
        show_usage
    fi

    if [ -n "$lease_file" ] && [ "$lease_file" != "-" ] && [ ! -f "$lease_file" ]; then
        echo "Error: Lease file '$lease_file' not found" >&2
        exit 1
    fi

    if [ -n "$config_file" ] && [ "$config_file" != "-" ] && [ ! -f "$config_file" ]; then
        echo "Error: Config file '$config_file' not found" >&2
        exit 1
    fi

    if [ -n "$config_file" ]; then
        if [ "$config_file" = "-" ]; then
            echo "Error: Config file cannot be read from stdin" >&2
            exit 1
        else
            process_config < "$config_file"
        fi
    fi

    if [ -n "$lease_file" ]; then
        if [ "$lease_file" = "-" ]; then
            process_leases
        else
            process_leases < "$lease_file"
        fi
    fi

    if [ "$output_file" = "-" ]; then
        output_leases
    else
        output_leases > "$output_file"
    fi
}

main
