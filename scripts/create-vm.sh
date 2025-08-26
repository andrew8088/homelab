#!/bin/bash

# Proxmox VM Creation Script for homelab-k3s
# VM ID: 100

set -e  # Exit on any error

VMID=101
VM_NAME="homelab-k3s"
ISO_PATH="local:iso/ubuntu-24.04.3-live-server-amd64.iso"
STORAGE_DISK="local"
STORAGE_EFI="local"

# SSD configuration for k3s storage
SSD_DRIVES=(
    "/dev/disk/by-id/ata-Samsung_SSD_870_QVO_8TB_S5VUNJ0W403153R"
    "/dev/disk/by-id/ata-Samsung_SSD_870_QVO_8TB_S5VUNJ0W407197T"
)

echo "Creating Proxmox VM: $VM_NAME (ID: $VMID)"

# Check if VM already exists
if qm status $VMID >/dev/null 2>&1; then
    echo "ERROR: VM with ID $VMID already exists!"
    echo "Use 'qm destroy $VMID' to remove it first, or choose a different ID."
    exit 1
fi

# Create the VM with basic settings
qm create $VMID \
    --name "$VM_NAME" \
    --ostype l26 \
    --machine q35 \
    --bios ovmf \
    --cpu host \
    --sockets 1 \
    --cores 3 \
    --memory 12288 \
    --balloon 2048 \
    --agent enabled=1 \
    --scsihw virtio-scsi-single \
    --bootdisk scsi0 \
    --boot order=scsi0

echo "VM created. Adding storage devices..."

# Add EFI disk
qm set $VMID --efidisk0 "${STORAGE_EFI}:1,efitype=4m,pre-enrolled-keys=1"

# Add main hard disk (local storage uses qcow2 format)
qm set $VMID --scsi0 "${STORAGE_DISK}:32,cache=writeback,discard=on"

# Add optimizations for single-socket homelab
qm set $VMID --numa 0 --tablet 0

# Add CD/DVD drive with ISO
qm set $VMID --ide2 "$ISO_PATH,media=cdrom"

echo "Storage configured (using local/qcow2). Adding SSD storage for k3s..."

# Add raw SSD passthrough for k3s persistent storage
if [ ${#SSD_DRIVES[@]} -gt 0 ]; then
    echo "Adding ${#SSD_DRIVES[@]} SSD(s) for k3s storage:"
    for i in "${!SSD_DRIVES[@]}"; do
        ssd_path="${SSD_DRIVES[$i]}"
        scsi_id=$((i + 2))  # Start at scsi2 (scsi0 is OS disk, scsi1 reserved)
        
        if [ -e "$ssd_path" ]; then
            echo "  Adding $ssd_path as scsi${scsi_id}"
            qm set $VMID --scsi${scsi_id} "$ssd_path"
        else
            echo "  WARNING: $ssd_path not found - skipping"
        fi
    done
else
    echo "  No SSDs configured in SSD_DRIVES array"
    echo "  Edit the script to add your SSD device IDs"
fi

echo "Setting up network..."

# Add network interface
qm set $VMID --net0 "virtio,bridge=vmbr0,firewall=1"

echo "Network configured. Setting display..."

# Set VGA/Display (Default graphics)
qm set $VMID --vga std

echo "VM configuration complete!"
echo ""
echo "VM Details:"
echo "  ID: $VMID"
echo "  Name: $VM_NAME"
echo "  Memory: 12288 MB (balloon min: 2048 MB)"
echo "  CPU: 3 cores (host type, NUMA disabled)"
echo "  OS Disk: 32GB qcow2 on $STORAGE_DISK"
echo "  SSD Storage: ${#SSD_DRIVES[@]} raw disk(s) for k3s"
echo "  ISO: $ISO_PATH"
echo "  Optimizations: NUMA disabled, tablet disabled"
echo ""
echo "Before running, find your SSDs with:"
echo "  lsblk"
echo "  ls -la /dev/disk/by-id/"
echo ""
echo "Edit SSD_DRIVES array in script with your actual device IDs"
echo ""
echo "To start the VM: qm start $VMID"
echo "To access console: qm terminal $VMID"
echo "To check status: qm status $VMID"

# Optionally start the VM
read -p "Start the VM now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Starting VM..."
    qm start $VMID
    echo "VM started! Access the console with: qm terminal $VMID"
fi
