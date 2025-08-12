# NVIDIA DGX B200 Firmware Update Toolkit v25.06.3

A comprehensive collection of sanitized, tested, and validated scripts for performing firmware updates on NVIDIA DGX B200 systems using firmware version 25.06.3. This toolkit provides reliable automation for bulk firmware management operations using parallel system firmware updates.

## Overview

This directory contains production-tested scripts and configuration files for performing firmware updates on NVIDIA DGX B200 systems using the `nvfwupd` tool (version 2.0.7) with parallel system firmware update capabilities. All scripts have been sanitized to remove identifying information and can be easily customized for different environments.

The scripts follow the official [NVIDIA DGX B200 Firmware Update Steps](https://docs.nvidia.com/dgx/dgxb200-fw-update-guide/sequence.html) and utilize [Parallel System Firmware Updates](https://docs.nvidia.com/dgx/dgxb200-fw-update-guide/parallel-update.html) for efficient bulk operations.

## Prerequisites

### Software Requirements
- **nvfwupd tool** version 2.0.7 or later
  - Download from: [NVIDIA Enterprise Support Portal](https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/nvfwupd_2.0.7-1_amd64.deb)
  - Installation: `sudo dpkg -i nvfwupd_2.0.7-1_amd64.deb`
- **System tools**: `curl`, `ipmitool`, `jq`, `awk`, `watch`
- **Bash shell** (tested on Ubuntu 24.04)
- **Cluster management tools**: `cmsh` (for monitoring system status)

### Network Requirements
- Network connectivity to BMC interfaces of target DGX B200 systems
- Valid BMC credentials (username/password)
- Proper firewall configuration for Redfish API access (HTTPS/443) and IPMI (UDP/623)

### Firmware Package Requirements
- **NVIDIA DGX B200 firmware package version 25.06.3**
  - Download from: [DGXB200_25.06.3.tar.gz](https://dgxdownloads.nvidia.com/custhelp/DGX_B200/firmware/DGXB200_25.06.3.tar.gz)
  - Extract in the same directory as the scripts: `tar -xzf DGXB200_25.06.3.tar.gz`
  - Contains separate packages for motherboard tray and GPU tray components
  - YAML configuration files reference extracted package paths

## Firmware Update Workflow

Follow this production-tested sequence for complete system updates, based on the official [NVIDIA DGX B200 Firmware Update Steps](https://docs.nvidia.com/dgx/dgxb200-fw-update-guide/sequence.html):

### Setup and Preparation

1. **Run the automated setup script** to configure the toolkit for your environment:
   ```bash
   # Make setup script executable (Linux/Unix only)
   chmod +x setup.sh
   
   # Run the setup script
   ./setup.sh
   ```
   
   The setup script will:
   - Install/configure nvfwupd if needed
   - Download and extract firmware packages automatically
   - Prompt for your IP ranges, hostnames, and BMC credentials
   - Generate properly configured YAML files for your systems
   - Update all scripts to use your actual values

2. **Initial connectivity check** and BMC reset:
   ```bash
   # Proactively reset BMC to ensure connectivity
   ./mc_reset.sh
   
   # Monitor that BMCs come back online
   watch -n2 'cmsh -c "device power status" | grep FAIL'
   # Wait until no systems show FAIL status
   ```

3. **Capture pre-update versions**:
   ```bash
   nvfwupd -c motherboard.yaml show_version > pre_update_versions_motherboard.txt
   nvfwupd -c gpu_tray_final.yaml show_version > pre_update_versions_gpu_tray.txt
   ```

### Update BMC

1. **Update BMC firmware**:
   ```bash
   nvfwupd -c bmc.yaml update_fw
   ```

2. **Reset BMC and wait for availability**:
   ```bash
   ./mc_reset.sh
   
   # Monitor BMC availability
   watch -n2 'cmsh -c "device power status" | grep FAIL'
   # Proceed when no systems show FAIL status
   ```

### Update Motherboard Tray

1. **Update motherboard components**:
   ```bash
   nvfwupd -c motherboard.yaml update_fw
   ```

### Update GPU Tray

1. **Update to intermediate GPU firmware**:
   ```bash
   nvfwupd -c gpu_tray_intermediate.yaml update_fw
   ```

2. **Verify background copy completion**:
   ```bash
   ./gpu_backgroundcopystatus.sh
   # Look for "BackgroundCopyStatus": "Completed" in output
   ```

3. **Power cycle systems**:
   ```bash
   ./power_cycle.sh
   
   # Monitor systems coming back online
   watch -n2 'cmsh -c "device status"'
   ```

4. **Update to final GPU firmware**:
   ```bash
   nvfwupd -c gpu_tray_final.yaml update_fw
   ```

5. **Final power cycle**:
   ```bash
   ./power_cycle.sh
   
   # Monitor systems coming back online
   watch -n2 'cmsh -c "device status"'
   ```

### Verification

1. **Confirm updates are complete**:
   ```bash
   nvfwupd -c motherboard.yaml show_version > post_update_versions_motherboard.txt
   nvfwupd -c gpu_tray_final.yaml show_version > post_update_versions_gpu_tray.txt
   ```

### Execute Background Copy Operations

1. **BMC background copy**:
   ```bash
   ./bmc_background_copy.sh
   
   # Monitor progress
   ./status_bmc_background.sh | grep "PercentComplete"
   ```

2. **BIOS background copy**:
   ```bash
   ./bios_background_copy.sh
   
   # Monitor progress
   ./status_bios_background.sh | grep "PercentComplete"
   ```

3. **Final system restart**:
   ```bash
   ./power_cycle.sh
   
   # Monitor systems coming back online
   watch -n2 'cmsh -c "device status"'
   ```

### Notes on Multi-Package YAML Configuration

Currently, the workflow uses separate YAML files for motherboard and GPU tray updates because the documentation does not clearly specify how to include multiple `PACKAGE` values with corresponding `UPDATE_PARAMETERS_TARGETS` in a single YAML file for multi-system operations. While `nvfwupd` supports multiple packages via CLI options for single systems, the YAML configuration for parallel updates requires separate files for different package types.

## Directory Structure

```
DGXB200_25.06.3/                        # Firmware toolkit for NVIDIA DGX B200 v25.06.3
├── Scripts/
│   ├── bios_background_copy.sh          # BIOS firmware background copy
│   ├── bmc_background_copy.sh           # BMC firmware background copy
│   ├── gpu_backgroundcopystatus.sh      # GPU background copy status checker
│   ├── mc_info.sh                       # BMC firmware version info
│   ├── mc_reset.sh                      # BMC cold reset utility
│   ├── parse_versions.sh                # Parse version logs for issues/updates needed
│   ├── power_cycle.sh                   # System power cycle utility
│   ├── setup.sh                         # Automated toolkit configuration script
│   ├── status_bios_background.sh        # BIOS update progress monitoring
│   └── status_bmc_background.sh         # BMC update progress monitoring
├── YAML Configurations/
│   ├── bmc.yaml                         # BMC-specific update configuration
│   ├── gpu_tray_final.yaml              # GPU tray final update config
│   ├── gpu_tray_intermediate.yaml       # GPU tray intermediate update config
│   └── motherboard.yaml                 # Motherboard update configuration
├── Firmware Packages/ (after extraction)
│   ├── packages/
│   │   ├── motherboard_tray/
│   │   │   └── nvfw_DGX_250629.1.0.fwpkg
│   │   └── GPU_tray/
│   │       ├── nvfw_DGX-HGX-B100-B200x8_250114.1.0.fwpkg (intermediate)
│   │       └── nvfw_DGX-HGX-B100-B200x8_250428.1.0.fwpkg (final)
└── Logs/ (generated during operations)
    ├── *_background_copy.log            # Background operation logs
    ├── power_cycle.log                  # Power cycle operation logs
    ├── mc_reset.log                     # MC reset operation logs
    ├── pre_update_versions_*.txt        # Pre-update version snapshots
    └── post_update_versions_*.txt       # Post-update version snapshots
```









## Version Log Analysis

The `parse_versions.sh` script helps analyze the verbose output from `nvfwupd show_version` commands, which can be overwhelming due to:
- Redundant information across multiple systems
- "N/A" entries for devices not covered by the current package
- Connection failures mixed with successful results

### Usage
```bash
# Parse any version log file
./parse_versions.sh <version_log_file> [output_file]

# Examples
./parse_versions.sh pre_update_versions_motherboard.txt
./parse_versions.sh post_update_versions_gpu_tray.txt custom_results.log
```

### What It Extracts
The parser creates a clean summary containing only:
1. **Connection Failures**: Systems that failed to retrieve firmware inventory from BMC
2. **Update Requirements**: Firmware devices where:
   - `Pkg Version` is NOT "N/A" (device covered by current package)
   - `Up-To-Date` is "No" (device needs updating)

### Output Format
- **Timestamp-based filename**: `YYYY.MM.DD.HH.MM_parsed_versions.log`
- **Structured sections**: Connection failures, systems needing updates, summary
- **Clean device tables**: Only relevant devices with actionable information
- **Statistics**: Total failures, systems needing updates, device counts

This eliminates the need to manually sift through hundreds of lines of redundant version information across multiple systems and packages.

## Monitoring and Troubleshooting

### Log Files
- All operations generate detailed logs in the working directory
- Monitor `nvfwupd_log.txt` for detailed update information
- Check `*_background_copy.log` files for background operation status

### Progress Monitoring
- Use `status_*_background.sh` scripts to monitor update progress
- Background copy status can be checked with `gpu_backgroundcopystatus.sh`
- Progress is reported as percentage complete

### Common Issues
1. **Authentication Failures**: Verify BMC credentials and network connectivity
2. **Package Not Found**: Ensure firmware package paths are correct and accessible
3. **Update Hangs**: Check system load and network stability
4. **Version Mismatch**: Verify package compatibility with target systems

## Safety Considerations

- **Test First**: Always test on a single system before bulk operations
- **Backup Configurations**: Save current system configurations before updates
- **Staged Updates**: Perform updates in manageable batches
- **Monitor Progress**: Use status scripts to track update completion
- **Power Management**: Ensure stable power supply during updates
- **Recovery Plan**: Have rollback procedures ready

## Reference Documentation

- [NVIDIA DGX B200 Firmware Update Guide](https://docs.nvidia.com/dgx/dgxb200-fw-update-guide)
- [nvfwupd Tool Documentation](https://docs.nvidia.com/dgx/dgxb200-fw-update-guide/#about-the-nvfwupd-command)
- [NVIDIA Enterprise Support Portal](https://enterprise-support.nvidia.com/)

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Review NVIDIA's official documentation:
   - [NVIDIA DGX B200 Firmware Update Steps](https://docs.nvidia.com/dgx/dgxb200-fw-update-guide/sequence.html)
   - [Parallel System Firmware Updates](https://docs.nvidia.com/dgx/dgxb200-fw-update-guide/parallel-update.html)
3. Contact NVIDIA Enterprise Support for firmware-related issues
4. Submit issues to this repository for script-specific problems

## Important Notes

- **Network Connectivity**: NVMe firmware updates and network card updates are not included in this iteration as they were not required for this release
- **Package Compatibility**: This toolkit is specifically designed for NVIDIA DGX B200 firmware package version 25.06.3
- **Testing**: Always test the complete workflow on a single system before performing bulk operations
- **Monitoring**: Use the provided monitoring commands to track system status throughout the update process

## License

This toolkit is provided as-is for educational and operational purposes. Refer to NVIDIA's licensing terms for firmware packages and tools.

---

**Note**: This toolkit was validated with nvfwupd version 2.0.7 and NVIDIA DGX B200 firmware version 25.06.3. Always refer to the latest NVIDIA documentation for the most current procedures and requirements.
