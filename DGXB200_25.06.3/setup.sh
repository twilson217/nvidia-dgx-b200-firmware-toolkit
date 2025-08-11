#!/bin/bash

# NVIDIA DGX B200 Firmware Update Toolkit Setup Script
# This script configures the toolkit for your environment

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
TEMP_DIR="$SCRIPT_DIR/temp_setup"

# Function to load existing configuration
load_existing_config() {
    if [[ -f "$ENV_FILE" ]]; then
        print_info "Found existing configuration file: $ENV_FILE"
        source "$ENV_FILE"
        return 0
    else
        return 1
    fi
}

# Function to prompt with default value
prompt_with_default() {
    local prompt="$1"
    local current_value="$2"
    local var_name="$3"
    local is_password="${4:-false}"
    
    if [[ -n "$current_value" ]]; then
        if [[ "$is_password" == "true" ]]; then
            read -p "$prompt [current: ****] (press Enter to keep current): " input
        else
            read -p "$prompt [current: $current_value] (press Enter to keep current): " input
        fi
        
        if [[ -z "$input" ]]; then
            eval "$var_name=\"$current_value\""
        else
            eval "$var_name=\"$input\""
        fi
    else
        if [[ "$is_password" == "true" ]]; then
            read -s -p "$prompt: " input
            echo
        else
            read -p "$prompt: " input
        fi
        eval "$var_name=\"$input\""
    fi
}

# Function to prompt with default value for passwords
prompt_password_with_default() {
    local prompt="$1"
    local current_value="$2"
    local var_name="$3"
    
    if [[ -n "$current_value" ]]; then
        read -s -p "$prompt [current password set] (press Enter to keep current, or type new): " input
        echo
        if [[ -z "$input" ]]; then
            eval "$var_name=\"$current_value\""
        else
            eval "$var_name=\"$input\""
        fi
    else
        read -s -p "$prompt: " input
        echo
        eval "$var_name=\"$input\""
    fi
}

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

# Function to confirm command execution
confirm_command() {
    local cmd="$1"
    echo -e "${YELLOW}About to run:${NC} $cmd"
    read -p "Confirm? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Command cancelled by user"
        exit 1
    fi
}

# Function to run command with confirmation
run_with_confirmation() {
    local cmd="$1"
    confirm_command "$cmd"
    eval "$cmd"
}

# Function to validate IP range format
validate_ip_range() {
    local input="$1"
    # Full IP range: 192.168.1.10-192.168.1.20
    if [[ $input =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}-[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    # Short IP range: 192.168.1.10-20
    elif [[ $input =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}-[0-9]+$ ]]; then
        return 0
    # Comma-separated list: 192.168.1.10,192.168.1.11,192.168.1.15
    elif [[ $input =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(,[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})*$ ]]; then
        return 0
    # Single IP: 192.168.1.10
    elif [[ $input =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to expand IP range
expand_ip_range() {
    local input="$1"
    
    if [[ $input == *","* ]]; then
        # Comma-separated list: 192.168.1.10,192.168.1.11,192.168.1.15
        echo "$input" | tr ',' '\n'
    elif [[ $input == *"-"* ]]; then
        if [[ $input =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.([0-9]{1,3})-([0-9]+)$ ]]; then
            # Short IP range like 192.168.1.10-20
            local prefix="${BASH_REMATCH[1]}"
            local start="${BASH_REMATCH[2]}"
            local end="${BASH_REMATCH[3]}"
            for ((i=start; i<=end; i++)); do
                echo "$prefix.$i"
            done
        elif [[ $input =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.([0-9]{1,3})-([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.([0-9]{1,3})$ ]]; then
            # Full IP range like 192.168.1.10-192.168.1.20
            local start_prefix="${BASH_REMATCH[1]}"
            local start_last="${BASH_REMATCH[2]}"
            local end_prefix="${BASH_REMATCH[3]}"
            local end_last="${BASH_REMATCH[4]}"
            
            # Validate that prefixes match
            if [[ "$start_prefix" != "$end_prefix" ]]; then
                print_error "IP range prefixes must match: $start_prefix vs $end_prefix"
                return 1
            fi
            
            # Generate the range
            for ((i=start_last; i<=end_last; i++)); do
                echo "$start_prefix.$i"
            done
        else
            print_error "Unrecognized IP range format: $input"
            return 1
        fi
    else
        # Single IP
        echo "$input"
    fi
}

print_info "=== NVIDIA DGX B200 Firmware Update Toolkit Setup ==="
print_info "This script will configure the toolkit for your environment."
echo

# Load existing configuration if available
if load_existing_config; then
    print_success "Loaded existing configuration. You can press Enter to keep current values."
    echo
else
    print_info "No existing configuration found. Setting up from scratch."
    echo
fi

# Check if nvfwupd is installed
print_info "Checking nvfwupd installation..."
if command -v nvfwupd &> /dev/null; then
    print_success "nvfwupd found in PATH: $(which nvfwupd)"
    NVFWUPD_PATH="nvfwupd"
else
    print_warning "nvfwupd not found in PATH"
    read -p "Is nvfwupd installed on this system? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "Please enter the full path to nvfwupd: " nvfwupd_path
        if [[ -x "$nvfwupd_path" ]]; then
            print_info "Adding nvfwupd to PATH for this session"
            export PATH="$(dirname "$nvfwupd_path"):$PATH"
            NVFWUPD_PATH="$nvfwupd_path"
        else
            print_error "nvfwupd not found at specified path or not executable"
            exit 1
        fi
    else
        print_info "Downloading and installing nvfwupd..."
        mkdir -p "$TEMP_DIR"
        cd "$TEMP_DIR"
        
        download_url="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/nvfwupd_2.0.7-1_amd64.deb"
        run_with_confirmation "wget '$download_url'"
        run_with_confirmation "sudo dpkg -i nvfwupd_2.0.7-1_amd64.deb"
        
        if command -v nvfwupd &> /dev/null; then
            print_success "nvfwupd installed successfully"
            NVFWUPD_PATH="nvfwupd"
        else
            print_error "nvfwupd installation failed"
            exit 1
        fi
        cd "$SCRIPT_DIR"
    fi
fi

# Check firmware files
print_info "Checking DGXB200_25.06.3 firmware files..."
read -p "Are the DGXB200_25.06.3 firmware files downloaded and extracted? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Please provide the absolute paths to the firmware files:"
    prompt_with_default "Motherboard package path" "$MOTHERBOARD_PACKAGE_PATH" "MOTHERBOARD_PACKAGE_PATH"
    prompt_with_default "GPU intermediate package path" "$GPU_INTERMEDIATE_PACKAGE_PATH" "GPU_INTERMEDIATE_PACKAGE_PATH"
    prompt_with_default "GPU final package path" "$GPU_FINAL_PACKAGE_PATH" "GPU_FINAL_PACKAGE_PATH"
    
    # Validate paths exist
    for path in "$MOTHERBOARD_PACKAGE_PATH" "$GPU_INTERMEDIATE_PACKAGE_PATH" "$GPU_FINAL_PACKAGE_PATH"; do
        if [[ ! -f "$path" ]]; then
            print_error "File not found: $path"
            exit 1
        fi
    done
else
    print_info "Downloading DGXB200_25.06.3 firmware package..."
    mkdir -p "$TEMP_DIR"
    cd "$SCRIPT_DIR"
    
    firmware_url="https://dgxdownloads.nvidia.com/custhelp/DGX_B200/firmware/DGXB200_25.06.3.tar.gz"
    run_with_confirmation "wget '$firmware_url'"
    
    print_info "Extracting firmware package..."
    run_with_confirmation "tar -xzf DGXB200_25.06.3.tar.gz"
    
    # Auto-detect paths from extraction
    print_info "Auto-detecting firmware file paths..."
    MOTHERBOARD_PACKAGE_PATH="$(find "$SCRIPT_DIR" -name "*nvfw_DGX_*.fwpkg" -path "*/motherboard_tray/*" | head -1)"
    GPU_INTERMEDIATE_PACKAGE_PATH="$(find "$SCRIPT_DIR" -name "*nvfw_DGX-HGX-B100-B200x8_*250114*.fwpkg" | head -1)"
    GPU_FINAL_PACKAGE_PATH="$(find "$SCRIPT_DIR" -name "*nvfw_DGX-HGX-B100-B200x8_*250428*.fwpkg" | head -1)"
    
    echo
    print_info "Detected firmware file paths:"
    echo "  Motherboard: $MOTHERBOARD_PACKAGE_PATH"
    echo "  GPU Intermediate: $GPU_INTERMEDIATE_PACKAGE_PATH"
    echo "  GPU Final: $GPU_FINAL_PACKAGE_PATH"
    echo
    
    read -p "Are these paths correct? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Please enter the correct paths:"
        prompt_with_default "Motherboard package path" "$MOTHERBOARD_PACKAGE_PATH" "MOTHERBOARD_PACKAGE_PATH"
        prompt_with_default "GPU intermediate package path" "$GPU_INTERMEDIATE_PACKAGE_PATH" "GPU_INTERMEDIATE_PACKAGE_PATH"
        prompt_with_default "GPU final package path" "$GPU_FINAL_PACKAGE_PATH" "GPU_FINAL_PACKAGE_PATH"
    fi
fi

# Get IP address configuration
print_info "Configuring IP address ranges..."
echo "Format examples:"
echo "  Range: 192.168.1.10-20 (expands to 192.168.1.10 through 192.168.1.20)"
echo "  List: 192.168.1.10,192.168.1.11,192.168.1.15"
echo "  Full range: 192.168.1.10-192.168.1.20"
echo

# Reconstruct current IP input if available
if [[ -n "$IP_PREFIX" && -n "$START_IP" && -n "$END_IP" ]]; then
    if [[ "$START_IP" == "$END_IP" ]]; then
        current_ip_input="$IP_PREFIX.$START_IP"
    else
        current_ip_input="$IP_PREFIX.$START_IP-$IP_PREFIX.$END_IP"
    fi
else
    current_ip_input=""
fi

# Get IP input with validation and re-prompting
while true; do
    if [[ -n "$current_ip_input" ]]; then
        read -p "Enter IP address range/list [current: $current_ip_input] (press Enter to keep current): " ip_input
        if [[ -z "$ip_input" ]]; then
            ip_input="$current_ip_input"
        fi
    else
        read -p "Enter IP address range/list: " ip_input
    fi
    
    if validate_ip_range "$ip_input"; then
        print_success "Valid IP range format detected"
        break
    else
        print_error "Invalid IP range format!"
        echo "Supported formats:"
        echo "  - Full range: 192.168.1.63-192.168.1.94"
        echo "  - Short range: 192.168.1.10-20"
        echo "  - List: 192.168.1.10,192.168.1.11,192.168.1.15"
        echo "  - Single IP: 192.168.1.10"
        echo
        print_warning "Please enter a valid format. NO DEFAULTS WILL BE USED."
        echo
        current_ip_input=""  # Clear invalid current value
    fi
done

# Parse the IP range for script variables
if [[ $ip_input =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.([0-9]{1,3})-([0-9]+)$ ]]; then
    # Short range like 192.168.1.10-20
    IP_PREFIX="${BASH_REMATCH[1]}"
    START_IP="${BASH_REMATCH[2]}"
    END_IP="${BASH_REMATCH[3]}"
elif [[ $ip_input =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.([0-9]{1,3})-([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.([0-9]{1,3})$ ]]; then
    # Full range like 192.168.1.63-192.168.1.94
    IP_PREFIX="${BASH_REMATCH[1]}"
    START_IP="${BASH_REMATCH[2]}"
    END_IP="${BASH_REMATCH[4]}"
elif [[ $ip_input =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.([0-9]{1,3})$ ]]; then
    # Single IP like 192.168.1.10
    IP_PREFIX="${BASH_REMATCH[1]}"
    START_IP="${BASH_REMATCH[2]}"
    END_IP="${BASH_REMATCH[2]}"
else
    # Comma-separated list - we'll use the first IP for prefix and handle specially
    first_ip=$(echo "$ip_input" | cut -d',' -f1)
    if [[ $first_ip =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        IP_PREFIX="${BASH_REMATCH[1]}"
        START_IP="${BASH_REMATCH[2]}"
        END_IP="${BASH_REMATCH[2]}"
        print_info "Using comma-separated list - scripts will use first IP for range variables"
    fi
fi

print_info "Parsed IP configuration:"
print_info "  IP Prefix: $IP_PREFIX"
print_info "  Start IP: $START_IP" 
print_info "  End IP: $END_IP"

# Get exclusions
if [[ -n "$SKIP_IP" ]]; then
    read -p "Do you want to exclude any IP addresses? [current exclusions: $SKIP_IP] (y/n): " -n 1 -r
else
    read -p "Do you want to exclude any IP addresses? (y/n): " -n 1 -r
fi
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [[ -n "$SKIP_IP" ]]; then
        read -p "Enter IP addresses to exclude (comma-separated) [current: $SKIP_IP] (press Enter to keep current): " exclude_ips
        if [[ -z "$exclude_ips" ]]; then
            exclude_ips="$SKIP_IP"
        fi
    else
        read -p "Enter IP addresses to exclude (comma-separated): " exclude_ips
    fi
    SKIP_IP="$exclude_ips"
else
    SKIP_IP=""
fi

# Function to parse hostname range
parse_hostname_range() {
    local input="$1"
    local ip_start="$2"
    local ip_end="$3"
    
    if [[ -z "$input" ]]; then
        # Use IP-based names
        echo "IP_BASED"
        return
    fi
    
    # Check for hostname range like b33-b64
    if [[ $input =~ ^([a-zA-Z0-9-]*[a-zA-Z-])([0-9]+)-([a-zA-Z0-9-]*[a-zA-Z-])([0-9]+)$ ]]; then
        local start_prefix="${BASH_REMATCH[1]}"
        local start_num="${BASH_REMATCH[2]}"
        local end_prefix="${BASH_REMATCH[3]}"
        local end_num="${BASH_REMATCH[4]}"
        
        # Validate that prefixes match
        if [[ "$start_prefix" != "$end_prefix" ]]; then
            print_error "Hostname range prefixes must match: $start_prefix vs $end_prefix"
            return 1
        fi
        
        # Validate that hostname range matches IP range count
        local hostname_count=$((end_num - start_num + 1))
        local ip_count=$((ip_end - ip_start + 1))
        
        if [[ $hostname_count -ne $ip_count ]]; then
            print_error "Hostname range count ($hostname_count) must match IP range count ($ip_count)"
            print_error "Hostnames: $start_prefix$start_num to $end_prefix$end_num"
            print_error "IPs: $ip_start to $ip_end"
            return 1
        fi
        
        echo "RANGE:$start_prefix:$start_num:$end_num"
        return
    fi
    
    # Check for comma-separated list
    if [[ $input == *","* ]]; then
        echo "LIST:$input"
        return
    fi
    
    # Treat as prefix
    echo "PREFIX:$input"
}

# Get hostname configuration
print_info "Configuring system hostnames..."
echo "Format examples:"
echo "  Range: b33-b64 (must match IP range count)"
echo "  List: dgx-node-01,dgx-node-02,dgx-node-05"
echo "  Prefix: dgx-cluster (generates dgx-cluster-01, dgx-cluster-02, etc.)"
echo

# Reconstruct current hostname input if available
current_hostname_input=""
if [[ "$HOSTNAME_TYPE" == "RANGE" && -n "$HOSTNAME_PREFIX" && -n "$HOSTNAME_START" && -n "$HOSTNAME_END" ]]; then
    current_hostname_input="$HOSTNAME_PREFIX$HOSTNAME_START-$HOSTNAME_PREFIX$HOSTNAME_END"
elif [[ "$HOSTNAME_TYPE" == "LIST" && -n "$HOSTNAME_LIST" ]]; then
    current_hostname_input="$HOSTNAME_LIST"
elif [[ "$HOSTNAME_TYPE" == "PREFIX" && -n "$SYSTEM_NAME_PREFIX" ]]; then
    current_hostname_input="$SYSTEM_NAME_PREFIX"
elif [[ "$HOSTNAME_TYPE" == "IP_BASED" ]]; then
    current_hostname_input=""  # Will show as default
fi

if [[ -n "$current_hostname_input" ]]; then
    read -p "Enter hostname range/list [current: $current_hostname_input] (press Enter to keep current): " hostname_input
    if [[ -z "$hostname_input" ]]; then
        hostname_input="$current_hostname_input"
    fi
elif [[ "$HOSTNAME_TYPE" == "IP_BASED" ]]; then
    read -p "Enter hostname range/list [current: IP-based names] (press Enter to keep current): " hostname_input
else
    read -p "Enter hostname range/list or press Enter to use IP-based names: " hostname_input
fi

# Parse hostname configuration
hostname_config=$(parse_hostname_range "$hostname_input" "$START_IP" "$END_IP")
if [[ $? -ne 0 ]]; then
    print_error "Invalid hostname configuration. Exiting."
    exit 1
fi

if [[ "$hostname_config" == "IP_BASED" ]]; then
    HOSTNAME_TYPE="IP_BASED"
    SYSTEM_NAME_PREFIX="dgx-system"
    print_info "Will use IP-based system names like dgx-system-$START_IP, dgx-system-$END_IP, etc."
elif [[ "$hostname_config" =~ ^RANGE:(.+):([0-9]+):([0-9]+)$ ]]; then
    HOSTNAME_TYPE="RANGE"
    HOSTNAME_PREFIX="${BASH_REMATCH[1]}"
    HOSTNAME_START="${BASH_REMATCH[2]}"
    HOSTNAME_END="${BASH_REMATCH[3]}"
    print_info "Will use hostname range: $HOSTNAME_PREFIX$HOSTNAME_START to $HOSTNAME_PREFIX$HOSTNAME_END"
elif [[ "$hostname_config" =~ ^LIST:(.+)$ ]]; then
    HOSTNAME_TYPE="LIST"
    HOSTNAME_LIST="${BASH_REMATCH[1]}"
    print_info "Will use hostname list: $HOSTNAME_LIST"
elif [[ "$hostname_config" =~ ^PREFIX:(.+)$ ]]; then
    HOSTNAME_TYPE="PREFIX"
    SYSTEM_NAME_PREFIX="${BASH_REMATCH[1]}"
    print_info "Will use hostname prefix: $SYSTEM_NAME_PREFIX (generates $SYSTEM_NAME_PREFIX-01, $SYSTEM_NAME_PREFIX-02, etc.)"
fi

# Get credentials
print_info "Configuring BMC credentials..."
prompt_with_default "BMC Username" "$BMC_USERNAME" "BMC_USERNAME"
prompt_password_with_default "BMC Password" "$BMC_PASSWORD" "BMC_PASSWORD"

print_info "Confirming BMC credentials are the same for all systems..."
read -p "Are the BMC username and password the same for ALL systems in your range? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "This toolkit requires the same BMC credentials for all systems"
    print_info "Please ensure all systems have the same BMC username and password, then run setup again"
    exit 1
fi

# Create .env file
print_info "Creating environment configuration file..."
cat > "$ENV_FILE" << EOF
# NVIDIA DGX B200 Firmware Update Toolkit Configuration
# Generated by setup.sh on $(date)

# Paths
NVFWUPD_PATH="$NVFWUPD_PATH"
MOTHERBOARD_PACKAGE_PATH="$MOTHERBOARD_PACKAGE_PATH"
GPU_INTERMEDIATE_PACKAGE_PATH="$GPU_INTERMEDIATE_PACKAGE_PATH"
GPU_FINAL_PACKAGE_PATH="$GPU_FINAL_PACKAGE_PATH"

# Network Configuration
IP_PREFIX="$IP_PREFIX"
START_IP="$START_IP"
END_IP="$END_IP"
SKIP_IP="$SKIP_IP"

# System Configuration
HOSTNAME_TYPE="$HOSTNAME_TYPE"
SYSTEM_NAME_PREFIX="$SYSTEM_NAME_PREFIX"
HOSTNAME_PREFIX="$HOSTNAME_PREFIX"
HOSTNAME_START="$HOSTNAME_START"
HOSTNAME_END="$HOSTNAME_END"
HOSTNAME_LIST="$HOSTNAME_LIST"

# BMC Credentials
BMC_USERNAME="$BMC_USERNAME"
BMC_PASSWORD="$BMC_PASSWORD"

# Target Platform
TARGET_PLATFORM="DGX"
EOF

print_success "Configuration saved to $ENV_FILE"

# Generate YAML files with actual values
print_info "Generating YAML configuration files with your values..."

# Function to generate system entries for YAML
generate_yaml_systems() {
    local package_path="$1"
    local targets="$2"
    local output=""
    local counter=0
    
    for ((i=START_IP; i<=END_IP; i++)); do
        if [[ -n "$SKIP_IP" ]] && [[ "$SKIP_IP" == *"$IP_PREFIX.$i"* ]]; then
            continue
        fi
        
        # Generate system name based on hostname type
        local system_name
        case "$HOSTNAME_TYPE" in
            "IP_BASED")
                system_name="$SYSTEM_NAME_PREFIX-$i"
                ;;
            "RANGE")
                local hostname_num=$((HOSTNAME_START + counter))
                system_name="$HOSTNAME_PREFIX$hostname_num"
                ;;
            "LIST")
                # Get the hostname from the list by position
                local hostname_array=(${HOSTNAME_LIST//,/ })
                if [[ $counter -lt ${#hostname_array[@]} ]]; then
                    system_name="${hostname_array[$counter]}"
                else
                    system_name="$HOSTNAME_PREFIX-$((counter + 1))"
                fi
                ;;
            "PREFIX")
                system_name="$SYSTEM_NAME_PREFIX-$(printf "%02d" $((counter + 1)))"
                ;;
            *)
                system_name="dgx-system-$i"
                ;;
        esac
        
        output+="- BMC_IP: \"$IP_PREFIX.$i\"\n"
        output+="  RF_USERNAME: \"$BMC_USERNAME\"\n"
        output+="  RF_PASSWORD: \"$BMC_PASSWORD\"\n"
        output+="  TARGET_PLATFORM: \"$TARGET_PLATFORM\"\n"
        output+="  PACKAGE: \"$package_path\"\n"
        output+="  UPDATE_PARAMETERS_TARGETS: $targets\n"
        output+="  SYSTEM_NAME: \"$system_name\"\n"
        
        ((counter++))
    done
    
    echo -e "$output"
}

# Generate BMC YAML
cat > "$SCRIPT_DIR/bmc.yaml" << EOF
# Disable Sanitize Log optionally
# Disabling SANITIZE_LOG prints system IPs and user credentials to the logs and screen
SANITIZE_LOG: False

# Set ParallelUpdate to True
ParallelUpdate: True

# Multi target input. Value is list of dicts.
# Generated by setup.sh on $(date)
Targets:
$(generate_yaml_systems "$MOTHERBOARD_PACKAGE_PATH" '{"Targets" :["/redfish/v1/UpdateService/FirmwareInventory/HostBMC_0"]}')
EOF

# Generate Motherboard YAML
cat > "$SCRIPT_DIR/motherboard.yaml" << EOF
# Disable Sanitize Log optionally
# Disabling SANITIZE_LOG prints system IPs and user credentials to the logs and screen
SANITIZE_LOG: False

# Set ParallelUpdate to True
ParallelUpdate: True

# Multi target input. Value is list of dicts.
# Generated by setup.sh on $(date)
Targets:
$(generate_yaml_systems "$MOTHERBOARD_PACKAGE_PATH" '{}')
EOF

# Generate GPU Intermediate YAML
cat > "$SCRIPT_DIR/gpu_tray_intermediate.yaml" << EOF
# Disable Sanitize Log optionally
# Disabling SANITIZE_LOG prints system IPs and user credentials to the logs and screen
SANITIZE_LOG: False

# Set ParallelUpdate to True
ParallelUpdate: True

# Multi target input. Value is list of dicts.
# Generated by setup.sh on $(date)
Targets:
$(generate_yaml_systems "$GPU_INTERMEDIATE_PACKAGE_PATH" '{"Targets" :["/redfish/v1/UpdateService/FirmwareInventory/HGX_0"]}')
EOF

# Generate GPU Final YAML
cat > "$SCRIPT_DIR/gpu_tray_final.yaml" << EOF
# Disable Sanitize Log optionally
# Disabling SANITIZE_LOG prints system IPs and user credentials to the logs and screen
SANITIZE_LOG: False

# Set ParallelUpdate to True
ParallelUpdate: True

# Multi target input. Value is list of dicts.
# Generated by setup.sh on $(date)
Targets:
$(generate_yaml_systems "$GPU_FINAL_PACKAGE_PATH" '{"Targets" :["/redfish/v1/UpdateService/FirmwareInventory/HGX_0"]}')
EOF

# Update shell scripts to source the .env file
print_info "Updating shell scripts to use configuration..."

for script in *.sh; do
    if [[ "$script" != "setup.sh" ]] && [[ -f "$script" ]]; then
        # Create backup
        cp "$script" "$script.backup"
        
        # Add source line after shebang
        (
            head -n 1 "$script"
            echo
            echo "# Source configuration"
            echo "SCRIPT_DIR=\"\$(cd \"\$(dirname \"\${BASH_SOURCE[0]}\")\" && pwd)\""
            echo "source \"\$SCRIPT_DIR/.env\""
            echo
            tail -n +2 "$script"
        ) > "$script.tmp" && mv "$script.tmp" "$script"
        
        # Replace placeholders with variables
        sed -i 's/<BMC_USERNAME>/$BMC_USERNAME/g' "$script"
        sed -i 's/<BMC_PASSWORD>/$BMC_PASSWORD/g' "$script"
        sed -i 's/<IP_PREFIX>/$IP_PREFIX/g' "$script"
        sed -i 's/<START_IP>/$START_IP/g' "$script"
        sed -i 's/<END_IP>/$END_IP/g' "$script"
        sed -i 's/<SKIP_IP>/$SKIP_IP/g' "$script"
        
        chmod +x "$script"
    fi
done

# Clean up
rm -rf "$TEMP_DIR"

print_success "Setup completed successfully!"
echo
print_info "Configuration summary:"
echo "  - YAML files generated with your system configuration"
echo "  - Shell scripts updated to use your values"
echo "  - Configuration saved to .env file"
echo
print_info "You can now run the firmware update workflow as described in the README.md"
print_warning "Remember to backup your system configurations before starting firmware updates!"
