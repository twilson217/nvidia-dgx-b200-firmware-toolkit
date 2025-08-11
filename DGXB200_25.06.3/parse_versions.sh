#!/bin/bash

# Source configuration if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    source "$SCRIPT_DIR/.env"
fi

# Parse NVIDIA DGX B200 firmware version logs
# Extracts only systems with failures or devices needing updates

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to show usage
show_usage() {
    echo "Usage: $0 <version_log_file> [output_file]"
    echo ""
    echo "Parses nvfwupd show_version output and extracts relevant information:"
    echo "  - Systems that failed to connect/retrieve firmware inventory"
    echo "  - Firmware devices where Pkg Version is not 'N/A' and Up-To-Date is 'No'"
    echo ""
    echo "Arguments:"
    echo "  version_log_file  Input log file from nvfwupd show_version command"
    echo "  output_file       Optional output file (default: auto-generated timestamp)"
    echo ""
    echo "Examples:"
    echo "  $0 pre_update_versions_motherboard.txt"
    echo "  $0 post_update_versions_gpu_tray.txt parsed_results.log"
}

# Check arguments
if [[ $# -lt 1 ]]; then
    show_usage
    exit 1
fi

INPUT_FILE="$1"
if [[ ! -f "$INPUT_FILE" ]]; then
    print_error "Input file not found: $INPUT_FILE"
    exit 1
fi

# Generate output filename if not provided
if [[ -n "$2" ]]; then
    OUTPUT_FILE="$2"
else
    TIMESTAMP=$(date +%Y.%m.%d.%H.%M)
    OUTPUT_FILE="${TIMESTAMP}_parsed_versions.log"
fi

print_info "Parsing firmware version log: $INPUT_FILE"
print_info "Output will be written to: $OUTPUT_FILE"

# Initialize variables
current_system=""
connection_status=""
system_model=""
part_number=""
serial_number=""
packages=""
temp_devices=""
failed_systems=()
systems_with_updates=()

# Create temporary file for processing
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

# Parse the input file
{
    echo "# NVIDIA DGX B200 Firmware Version Analysis"
    echo "# Generated: $(date)"
    echo "# Source: $INPUT_FILE"
    echo "# Criteria: Connection failures OR (Pkg Version != 'N/A' AND Up-To-Date = 'No')"
    echo ""
    echo "========================================================================"
    echo ""
} > "$OUTPUT_FILE"

# First pass: identify failed connections
print_info "Identifying connection failures..."
connection_failures=0
while IFS= read -r line; do
    if [[ "$line" =~ ^Error.*Failed\ to\ retrieve\ firmware\ inventory ]]; then
        ((connection_failures++))
    fi
done < "$INPUT_FILE"

if [[ $connection_failures -gt 0 ]]; then
    {
        echo "CONNECTION FAILURES: $connection_failures systems"
        echo "----------------------------------------"
        echo "These systems failed to retrieve firmware inventory from BMC:"
        echo ""
    } >> "$OUTPUT_FILE"
    
    # Count and report failed connections
    failure_count=0
    while IFS= read -r line; do
        if [[ "$line" =~ ^Error.*Failed\ to\ retrieve\ firmware\ inventory ]]; then
            ((failure_count++))
            echo "  System $failure_count: Connection failed" >> "$OUTPUT_FILE"
        fi
    done < "$INPUT_FILE"
    
    echo "" >> "$OUTPUT_FILE"
    echo "======================================================================" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
fi

# Second pass: parse systems and identify update requirements
print_info "Analyzing firmware devices requiring updates..."

systems_needing_updates=0
total_devices_needing_updates=0

while IFS= read -r line; do
    # Detect system information
    if [[ "$line" =~ ^Displaying\ version\ info\ for\ (.+)$ ]]; then
        current_system="${BASH_REMATCH[1]}"
        connection_status=""
        system_model=""
        part_number=""
        serial_number=""
        packages=""
        temp_devices=""
        
    elif [[ -n "$current_system" ]]; then
        # Parse system metadata
        if [[ "$line" =~ ^System\ Model:\ (.+)$ ]]; then
            system_model="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^Part\ number:\ (.+)$ ]]; then
            part_number="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^Serial\ number:\ (.+)$ ]]; then
            serial_number="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^Packages:\ (.+)$ ]]; then
            packages="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^Connection\ Status:\ (.+)$ ]]; then
            connection_status="${BASH_REMATCH[1]}"
        
        # Parse firmware device lines
        elif [[ "$line" =~ ^([A-Za-z0-9_]+)[[:space:]]+([[:print:]]+)[[:space:]]+([[:print:]]+)[[:space:]]+([[:print:]]+)[[:space:]]*$ ]]; then
            device_name="${BASH_REMATCH[1]}"
            sys_version="${BASH_REMATCH[2]}"
            pkg_version="${BASH_REMATCH[3]}"
            up_to_date="${BASH_REMATCH[4]}"
            
            # Remove leading/trailing whitespace
            device_name=$(echo "$device_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            sys_version=$(echo "$sys_version" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            pkg_version=$(echo "$pkg_version" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            up_to_date=$(echo "$up_to_date" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            # Skip header lines
            if [[ "$device_name" == "AP" ]] || [[ "$device_name" == "-------" ]]; then
                continue
            fi
            
            # Check if device needs update (Pkg Version != "N/A" AND Up-To-Date = "No")
            if [[ "$pkg_version" != "N/A" ]] && [[ "$up_to_date" == "No" ]]; then
                if [[ -z "$temp_devices" ]]; then
                    temp_devices="$device_name|$sys_version|$pkg_version|$up_to_date"
                else
                    temp_devices="$temp_devices"$'\n'"$device_name|$sys_version|$pkg_version|$up_to_date"
                fi
                ((total_devices_needing_updates++))
            fi
        
        # End of system section (separator line or new system)
        elif [[ "$line" =~ ^-{50,}$ ]] || [[ "$line" =~ ^Displaying\ version\ info\ for ]]; then
            if [[ -n "$current_system" ]] && [[ -n "$temp_devices" ]]; then
                # This system has devices needing updates
                ((systems_needing_updates++))
                
                {
                    echo "SYSTEM: $current_system"
                    echo "Model: $system_model"
                    echo "Part Number: $part_number"
                    echo "Serial Number: $serial_number"
                    echo "Packages: $packages"
                    echo "Connection Status: $connection_status"
                    echo ""
                    echo "Devices Requiring Updates:"
                    echo "Device Name                             Sys Version                    Pkg Version                    Up-To-Date"
                    echo "-------                                 -----------                    -----------                    ----------"
                    
                    while IFS='|' read -r dev_name sys_ver pkg_ver upd_status; do
                        printf "%-40s %-30s %-30s %-10s\n" "$dev_name" "$sys_ver" "$pkg_ver" "$upd_status"
                    done <<< "$temp_devices"
                    
                    echo ""
                    echo "----------------------------------------"
                    echo ""
                } >> "$OUTPUT_FILE"
            fi
            
            # Reset for potential new system
            if [[ "$line" =~ ^Displaying\ version\ info\ for ]]; then
                current_system="${line#Displaying version info for }"
                temp_devices=""
            else
                current_system=""
                temp_devices=""
            fi
        fi
    fi
done < "$INPUT_FILE"

# Handle last system if file doesn't end with separator
if [[ -n "$current_system" ]] && [[ -n "$temp_devices" ]]; then
    ((systems_needing_updates++))
    
    {
        echo "SYSTEM: $current_system"
        echo "Model: $system_model"
        echo "Part Number: $part_number"
        echo "Serial Number: $serial_number"
        echo "Packages: $packages"
        echo "Connection Status: $connection_status"
        echo ""
        echo "Devices Requiring Updates:"
        echo "Device Name                             Sys Version                    Pkg Version                    Up-To-Date"
        echo "-------                                 -----------                    -----------                    ----------"
        
        while IFS='|' read -r dev_name sys_ver pkg_ver upd_status; do
            printf "%-40s %-30s %-30s %-10s\n" "$dev_name" "$sys_ver" "$pkg_ver" "$upd_status"
        done <<< "$temp_devices"
        
        echo ""
        echo "----------------------------------------"
        echo ""
    } >> "$OUTPUT_FILE"
fi

# Add summary
{
    echo ""
    echo "========================================================================"
    echo "SUMMARY"
    echo "========================================================================"
    echo "Connection Failures: $connection_failures systems"
    echo "Systems with Updates Needed: $systems_needing_updates systems"
    echo "Total Devices Needing Updates: $total_devices_needing_updates devices"
    echo ""
    echo "Analysis completed: $(date)"
} >> "$OUTPUT_FILE"

# Print results
print_success "Parsing completed!"
echo ""
print_info "Results Summary:"
echo "  Connection Failures: $connection_failures systems"
echo "  Systems with Updates Needed: $systems_needing_updates systems"
echo "  Total Devices Needing Updates: $total_devices_needing_updates devices"
echo ""
print_success "Parsed results saved to: $OUTPUT_FILE"

# Suggest next steps
if [[ $connection_failures -gt 0 ]] || [[ $systems_needing_updates -gt 0 ]]; then
    print_warning "Issues found that require attention:"
    if [[ $connection_failures -gt 0 ]]; then
        echo "  - $connection_failures systems have connection failures"
    fi
    if [[ $systems_needing_updates -gt 0 ]]; then
        echo "  - $systems_needing_updates systems have devices requiring updates"
    fi
else
    print_success "All systems are up-to-date with no connection issues!"
fi
