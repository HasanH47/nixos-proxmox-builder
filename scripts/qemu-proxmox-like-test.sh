#!/usr/bin/env bash
# Simulasi kasar Proxmox: root disk di VirtIO SCSI (scsi0) + ISO NoCloud terpisah (mirip ide2).
# Tidak memerlukan Proxmox; cukup QEMU + alat untuk bikin ISO seed (xorriso atau genisoimage).
#
# Contoh:
#   ./scripts/qemu-proxmox-like-test.sh ./output/nixos-template.qcow2
#   TEST_SSH_PUB=~/.ssh/id_ed25519.pub ./scripts/qemu-proxmox-like-test.sh ./output/nixos-template.qcow2
#   nix shell 'nixpkgs#xorriso' 'nixpkgs#qemu' -c ./scripts/qemu-proxmox-like-test.sh ./output/result/nixos-template.qcow2
#   (di zsh quote wajib pada 'nixpkgs#…' agar # bukan glob)
#
# Lingkungan:
#   TEST_SSH_PUB     - file public key untuk user-data (default: ~/.ssh/id_ed25519.pub)
#   TEST_CIUSER      - nama user yang dibuat cloud-init (default: hasanh47)
#   QEMU_EXTRA       - arg tambahan ke qemu (mis. -display none)
#   QEMU_UEFI        - jika "1", pakai firmware UEFI (OVMF) — butuh OVMF_CODE.fd + OVMF_VARS.fd di PATH distro
#   QEMU_MEMORY      - RAM MiB (default: 2048)
#   QEMU_SMP         - vCPU (default: 2)

set -euo pipefail

print_usage() {
  echo "Usage: $0 [options] /path/to/disk.qcow2" >&2
  echo "  --disk scsi          VirtIO SCSI + scsi-hd (default; mirip Proxmox scsi0)" >&2
  echo "  --disk virtio-blk    virtio-blk (mirip Proxmox virtio0)" >&2
}

usage_error() {
  print_usage
  exit 1
}

DISK_BUS="scsi"
POS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk)
      [[ $# -ge 2 ]] || usage_error
      case "$2" in
        scsi|virtio-blk) DISK_BUS="$2" ;;
        *) echo "Unknown --disk value: $2 (use scsi or virtio-blk)" >&2; exit 1 ;;
      esac
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      POS+=("$1")
      shift
      ;;
  esac
done
set -- "${POS[@]}"

[[ $# -ge 1 ]] || usage_error
QCOW="$(readlink -f "$1")"
[[ -f "$QCOW" ]] || { echo "File not found: $QCOW" >&2; exit 1; }

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/qemu-proxmox-test.XXXXXX")"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

NO="$WORKDIR/nocloud"
mkdir -p "$NO"

CIUSER="${TEST_CIUSER:-hasanh47}"

PUB_FILE="${TEST_SSH_PUB:-$HOME/.ssh/id_ed25519.pub}"
SSH_LINE=""
if [[ -f "$PUB_FILE" ]]; then
  SSH_LINE="$(cat "$PUB_FILE")"
else
  echo "WARN: $PUB_FILE tidak ada; user-data tanpa ssh_authorized_keys (set TEST_SSH_PUB)" >&2
fi

cat > "$NO/meta-data" <<EOF
instance-id: qemu-proxmox-like-$(date +%s)
local-hostname: nixos-qemu-test
EOF

# network: virtio_net + DHCP (slirp QEMU) — mirip ipconfig0 ip=dhcp di Proxmox
NETWORK_YAML="$(cat <<'NET'
network:
  version: 2
  ethernets:
    id0:
      match:
        driver: virtio_net
      dhcp4: true
NET
)"

if [[ -n "$SSH_LINE" ]]; then
  {
    printf '%s\n' '#cloud-config' "$NETWORK_YAML" '' 'users:' "  - name: $CIUSER" '    groups: [sudo]' '    lock_passwd: true' '    ssh_authorized_keys:'
    printf '      - %s\n' "$SSH_LINE"
  } >"$NO/user-data"
else
  {
    printf '%s\n' '#cloud-config' "$NETWORK_YAML" '' 'users:' "  - name: $CIUSER" '    groups: [sudo]' '    lock_passwd: true'
  } >"$NO/user-data"
fi

SEED_ISO="$WORKDIR/seed.iso"
if command -v xorrisofs >/dev/null 2>&1; then
  ( cd "$NO" && xorrisofs -output "$SEED_ISO" -volid cidata -joliet -rock user-data meta-data )
elif command -v genisoimage >/dev/null 2>&1; then
  genisoimage -output "$SEED_ISO" -volid cidata -r -J "$NO"
else
  echo "Butuh xorrisofs (nixpkgs xorriso) atau genisoimage untuk membuat ISO NoCloud." >&2
  echo "  nix shell 'nixpkgs#xorriso' -c $0 $*" >&2
  exit 1
fi

MEM="${QEMU_MEMORY:-2048}"
SMP="${QEMU_SMP:-2}"

QEMU_BIN="${QEMU_BIN:-qemu-system-x86_64}"
if ! command -v "$QEMU_BIN" >/dev/null 2>&1; then
  echo "qemu-system-x86_64 tidak di PATH" >&2
  exit 1
fi

# QEMU perlu buka QCOW2 dengan akses tulis (metadata). Path di /nix/store dan
# banyak image hasil nix build hanya read-only → overlay di $WORKDIR.
DISK_QEMU="$QCOW"
if [[ "$QCOW" == /nix/store/* ]] || [[ ! -w "$QCOW" ]]; then
  if ! command -v qemu-img >/dev/null 2>&1; then
    echo "Butuh qemu-img (sama paket qemu) untuk overlay dari image read-only / nix store." >&2
    exit 1
  fi
  DISK_QEMU="$WORKDIR/run-overlay.qcow2"
  qemu-img create -f qcow2 -F qcow2 -b "$QCOW" "$DISK_QEMU" >/dev/null
  echo "INFO: memakai overlay tulis $DISK_QEMU (backing read-only: $QCOW)" >&2
fi

# Akselerasi: KVM jika ada
ACCEL="tcg"
if [[ -r /dev/kvm ]] && [[ -w /dev/kvm ]]; then
  ACCEL="kvm"
fi

FW_ARGS=()
if [[ "${QEMU_UEFI:-0}" == "1" ]]; then
  # Lokasi umum (sesuaikan distro); override dengan QEMU_OVMF_CODE / QEMU_OVMF_VARS jika perlu
  OVMF_CODE="${QEMU_OVMF_CODE:-}"
  OVMF_VARS_TEMPLATE="${QEMU_OVMF_VARS:-}"
  if [[ -z "$OVMF_CODE" ]]; then
    for cand in \
      /usr/share/edk2/ovmf/OVMF_CODE.fd \
      /usr/share/qemu/edk2-x64-code.fd \
      /nix/store/*/share/qemu/edk2-x86_64-code.fd; do
      if [[ -f $cand ]]; then OVMF_CODE="$cand"; break; fi
    done
  fi
  if [[ -z "$OVMF_VARS_TEMPLATE" ]]; then
    for cand in \
      /usr/share/edk2/ovmf/OVMF_VARS.fd \
      /usr/share/qemu/edk2-x64-vars.fd \
      /nix/store/*/share/qemu/edk2-x86_64-vars.fd; do
      if [[ -f $cand ]]; then OVMF_VARS_TEMPLATE="$cand"; break; fi
    done
  fi
  if [[ -z "$OVMF_CODE" || -z "$OVMF_VARS_TEMPLATE" ]]; then
    echo "QEMU_UEFI=1 but OVMF firmware not found; set QEMU_OVMF_CODE and QEMU_OVMF_VARS" >&2
    exit 1
  fi
  OVMF_VARS_RW="$WORKDIR/ovmf_vars.fd"
  cp -f "$OVMF_VARS_TEMPLATE" "$OVMF_VARS_RW"
  FW_ARGS+=(
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
    -drive "if=pflash,format=raw,file=$OVMF_VARS_RW"
  )
fi

echo "=== QEMU (Proxmox-like) ===" >&2
echo "  Root disk : $DISK_BUS — $DISK_QEMU" >&2
echo "  Cloud-init: ISO NoCloud (cidata) — $SEED_ISO" >&2
echo "  Serial    : stdio (konsol)" >&2
echo "  Usernet   : guest SSH hostfwd tcp::2222 -> :22" >&2
echo "" >&2

DISK_ARGS=()
if [[ "$DISK_BUS" == "virtio-blk" ]]; then
  DISK_ARGS+=( -drive "file=$DISK_QEMU,if=virtio,format=qcow2" )
else
  DISK_ARGS+=(
    -drive "file=$DISK_QEMU,if=none,id=disk0,format=qcow2"
    -device virtio-scsi-pci,id=scsi0
    -device scsi-hd,drive=disk0,bus=scsi0.0
  )
fi

exec "$QEMU_BIN" \
  -machine "type=q35,accel=$ACCEL" \
  -cpu "${QEMU_CPU:-max}" \
  -m "$MEM" \
  -smp "$SMP" \
  "${FW_ARGS[@]}" \
  -object rng-random,filename=/dev/urandom,id=rng0 \
  -device virtio-rng-pci,rng=rng0 \
  "${DISK_ARGS[@]}" \
  -drive "file=$SEED_ISO,media=cdrom,readonly=on" \
  -netdev "user,id=net0,hostfwd=tcp::2222-:22" \
  -device virtio-net-pci,netdev=net0 \
  -serial mon:stdio \
  -display none \
  ${QEMU_EXTRA:-}
