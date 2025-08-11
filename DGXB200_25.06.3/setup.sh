#!/bin/bash

# NVIDIA DGX B200 Firmware Update Toolkit Setup Script
# This script configures the toolkit for your environment

set -e  # Exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
TEMP_DIR="$SCRIPT_DIR/temp_setup"

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
    if [[ $input =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}-[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || \
       [[ $input =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}(,[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})*$ ]] || \
       [[ $input =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}-[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to expand IP range
expand_ip_range() {
    local input="$1"
    local ip_list=""
    
    if [[ $input == *","* ]]; then
        # Comma-separated list
        echo "$input" | tr ',' '\n'
    elif [[ $input == *"-"* ]]; then
        if [[ $input =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.([0-9]{1,3})-([0-9]+)$ ]]; then
            # IP range like 192.168.1.10-20
            local prefix="${BASH_REMATCH[1]}"
            local start="${BASH_REMATCH[2]}"
            local end="${BASH_REMATCH[3]}"
            for ((i=start; i<=end; i++)); do
                echo "$prefix.$i"
            done
        else
            # Full IP range like 192.168.1.10-192.168.1.20
            # This is more complex, for now just return the input
            echo "$input"
        fi
    else
        # Single IP
        echo "$input"
    fi
}

print_info "=== NVIDIA DGX B200 Firmware Update Toolkit Setup ==="
print_info "This script will configure the toolkit for your environment."
echo

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
    read -p "Motherboard package path: " MOTHERBOARD_PACKAGE_PATH
    read -p "GPU intermediate package path: " GPU_INTERMEDIATE_PACKAGE_PATH
    read -p "GPU final package path: " GPU_FINAL_PACKAGE_PATH
    
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
        read -p "Motherboard package path: " MOTHERBOARD_PACKAGE_PATH
        read -p "GPU intermediate package path: " GPU_INTERMEDIATE_PACKAGE_PATH
        read -p "GPU final package path: " GPU_FINAL_PACKAGE_PATH
    fi
fi

# Get IP address configuration
print_info "Configuring IP address ranges..."
echo "Format examples:"
echo "  Range: 192.168.1.10-20 (expands to 192.168.1.10 through 192.168.1.20)"
echo "  List: 192.168.1.10,192.168.1.11,192.168.1.15"
echo "  Full range: 192.168.1.10-192.168.1.20"
echo

read -p "Enter IP address range/list: " ip_input
if ! validate_ip_range "$ip_input"; then
    print_warning "Invalid format, but continuing..."
fi

# Extract IP prefix and range for scripts
if [[ $ip_input =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\.([0-9]{1,3})-([0-9]+)$ ]]; then
    IP_PREFIX="${BASH_REMATCH[1]}"
    START_IP="${BASH_REMATCH[2]}"
    END_IP="${BASH_REMATCH[3]}"
elif [[ $ip_input =~ ^([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\. ]]; then
    IP_PREFIX="${BASH_REMATCH[1]}"
    START_IP="1"
    END_IP="254"
    print_info "Using default range 1-254 for IP prefix $IP_PREFIX"
else
    print_info "Complex IP range detected, you may need to manually adjust scripts"
    IP_PREFIX="192.168.1"
    START_IP="1"
    END_IP="254"
fi

# Get exclusions
read -p "Do you want to exclude any IP addresses? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter IP addresses to exclude (comma-separated): " exclude_ips
    SKIP_IP="$exclude_ips"
else
    SKIP_IP=""
fi

# Get hostname configuration
print_info "Configuring system hostnames..."
echo "Format examples:"
echo "  Range: dgx-01-dgx-10"
echo "  List: dgx-node-01,dgx-node-02,dgx-node-05"
echo
read -p "Enter hostname range/list or press Enter to use IP-based names: " hostname_input

if [[ -z "$hostname_input" ]]; then
    SYSTEM_NAME_PREFIX="dgx-system"
    print_info "Will use IP-based system names like dgx-system-31, dgx-system-32, etc."
else
    SYSTEM_NAME_PREFIX="$hostname_input"
fi

# Get credentials
print_info "Configuring BMC credentials..."
read -p "BMC Username: " BMC_USERNAME
read -s -p "BMC Password: " BMC_PASSWORD
echo

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
SYSTEM_NAME_PREFIX="$SYSTEM_NAME_PREFIX"

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
    
    for ((i=START_IP; i<=END_IP; i++)); do
        if [[ -n "$SKIP_IP" ]] && [[ "$SKIP_IP" == *"$IP_PREFIX.$i"* ]]; then
            continue
        fi
        
        local system_name="${SYSTEM_NAME_PREFIX}-$(printf "%02d" $((i - START_IP + 1)))"
        
        output+="- BMC_IP: \"$IP_PREFIX.$i\"\n"
        output+="  RF_USERNAME: \"$BMC_USERNAME\"\n"
        output+="  RF_PASSWORD: \"$BMC_PASSWORD\"\n"
        output+="  TARGET_PLATFORM: \"$TARGET_PLATFORM\"\n"
        output+="  PACKAGE: \"$package_path\"\n"
        output+="  UPDATE_PARAMETERS_TARGETS: $targets\n"
        output+="  SYSTEM_NAME: \"$system_name\"\n"
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
