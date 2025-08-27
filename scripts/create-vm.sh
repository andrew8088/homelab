#!/bin/bash

# Proxmox VM Creation Script for homelab-k3s
# VM ID: 101

set -e  # Exit on any error

VMID=101
VM_NAME="homelab-k3s"
ISO_PATH="local:iso/ubuntu-24.04.3-live-server-amd64.iso"
STORAGE_DISK="local-lvm"
STORAGE_EFI="local-lvm"

# Storage drives for k3s - All three 8TB drives available on Proxmox host
STORAGE_DRIVES=(
    "/dev/disk/by-id/ata-Samsung_SSD_870_QVO_8TB_S5VUNJ0W403153R"  # First Samsung SSD (sdc)
    "/dev/disk/by-id/ata-Samsung_SSD_870_QVO_8TB_S5VUNJ0W407197T"  # Second Samsung SSD (sdd)
    "/dev/disk/by-id/ata-ST8000VN004-3CP101_WWZ8N40X"              # Seagate USB drive (sde)
)

# Mount points to create (matching your test VM structure)
MOUNT_POINTS=("/mnt/primary" "/mnt/backup" "/mnt/external")

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

# Add CD/DVD drive with ISO
qm set $VMID --ide2 "$ISO_PATH,media=cdrom"

echo "Storage configured (using local/qcow2). Adding optimizations..."

# Add optimizations for single-socket homelab
qm set $VMID --numa 0 --tablet 0

echo "Optimizations applied. Adding storage drives..."

# Add raw disk passthrough for storage drives
if [ ${#STORAGE_DRIVES[@]} -gt 0 ]; then
    echo "Adding ${#STORAGE_DRIVES[@]} storage drive(s):"
    for i in "${!STORAGE_DRIVES[@]}"; do
        drive_path="${STORAGE_DRIVES[$i]}"
        scsi_id=$((i + 1))  # Start at scsi1 (scsi0 is OS disk)
        
        if [ -e "$drive_path" ]; then
            echo "  Adding $drive_path as scsi${scsi_id}"
            qm set $VMID --scsi${scsi_id} "$drive_path"
        else
            echo "  WARNING: $drive_path not found - skipping"
        fi
    done
else
    echo "  No storage drives configured in STORAGE_DRIVES array"
    echo "  Edit the script to add your drive device IDs"
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
echo "  Storage Drives: ${#STORAGE_DRIVES[@]} raw disk(s) for k3s"
echo "  Expected mounts: ${MOUNT_POINTS[*]}"
echo "  ISO: $ISO_PATH"
echo "  Optimizations: NUMA disabled, tablet disabled"
echo ""
echo "After VM creation, you'll need to mount the existing partitions:"
echo "  # The Samsung SSDs already have data - just mount the existing partitions"
echo "  # The USB device will appear as another drive (likely /dev/sdd)"
echo "  sudo mkdir -p ${MOUNT_POINTS[*]}"
echo "  # Check partition layout first:"
echo "  lsblk"
echo "  # Mount existing partitions (adjust partition numbers as needed):"
echo "  sudo mount /dev/sdb1 /mnt/primary    # First Samsung SSD"
echo "  sudo mount /dev/sdc1 /mnt/backup     # Second Samsung SSD" 
echo "  sudo mount /dev/sdd1 /mnt/external   # USB drive"
echo "  # Add to /etc/fstab for persistent mounts"
echo "  # Your existing data will be preserved and accessible to k3s pods"
echo ""
echo "Find your drives with:"
echo "  lsblk"
echo "  ls -la /dev/disk/by-id/"
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
