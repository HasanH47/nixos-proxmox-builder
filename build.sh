#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# NixOS 25.11 Proxmox Image Builder
# Jalankan di Linux apapun + Nix (tanpa Docker)
# ============================================================

OUTPUT_DIR="$(pwd)/output"

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# --- Cek Nix ---
if ! command -v nix &>/dev/null; then
  error "Nix tidak ditemukan. Pastikan sudah install dan environment tersource. Contoh: . ~/.nix-profile/etc/profile.d/nix.sh"
fi

# --- Cek SSH key di configuration.nix ---
if grep -q "# Tambahkan SSH public key kamu di sini" configuration.nix && \
   ! grep -qE '"ssh-(rsa|ed25519|ecdsa)' configuration.nix; then
  warn "SSH public key belum ditambahkan di configuration.nix!"
  warn "Edit configuration.nix dan tambahkan key kamu di bagian authorizedKeys.keys"
  echo ""
  read -rp "Lanjut build tanpa SSH key? (y/N): " yn
  [[ "$yn" =~ ^[Yy]$ ]] || exit 0
fi

# --- Buat output dir ---
mkdir -p "$OUTPUT_DIR"

info "Jalankan build NixOS 25.11 Proxmox image..."
info "Ini akan memakan waktu cukup lama (15-45 menit tergantung koneksi & CPU)"
echo ""

FORMAT="${1:-qcow2}"

case "$FORMAT" in
  qcow2|proxmox)
    ;;
  *)
    error "Format tidak dikenali: $FORMAT (pilih: qcow2 | proxmox)"
    ;;
esac

OUT_LINK="$OUTPUT_DIR/result"
rm -f "$OUT_LINK" 2>/dev/null || true

# zsh akan melakukan globbing pada `#` kalau tidak di-quote.
if [[ "$FORMAT" == "qcow2" ]]; then
  nix build -L '.#qcow2-image' --out-link "$OUT_LINK"
else
  nix build -L '.#proxmox-image' --out-link "$OUT_LINK"
fi

# --- Cari file VMA hasil build ---
VMA_FILE=$(find "$OUTPUT_DIR/result" -name "*.vma.zst" 2>/dev/null | head -1)
QCOW2_FILE=$(find -L "$OUTPUT_DIR/result" -maxdepth 2 -name "*.qcow2" 2>/dev/null | head -1)

if [[ -z "$VMA_FILE" ]]; then
  # Coba cari di dalam result symlink
  VMA_FILE=$(find -L "$OUTPUT_DIR" -name "*.vma.zst" 2>/dev/null | head -1)
fi

echo ""
info "============================================"
info "Build selesai!"
info "============================================"

if [[ "$FORMAT" == "qcow2" && -n "$QCOW2_FILE" ]]; then
  info "File QCOW2: $QCOW2_FILE"
  ls -lh "$QCOW2_FILE"
elif [[ "$FORMAT" == "proxmox" && -n "$VMA_FILE" ]]; then
  info "File VMA: $VMA_FILE"
  ls -lh "$VMA_FILE"
  echo ""
  info "Langkah selanjutnya - Copy ke Proxmox:"
  echo ""
  echo "  scp \"$VMA_FILE\" root@<proxmox-host>:/tmp/"
  echo ""
  info "Lalu di shell Proxmox, restore sebagai VM:"
  echo ""
  echo "  qmrestore /tmp/$(basename "$VMA_FILE") <VMID> --storage local-lvm"
  echo ""
  info "Contoh:"
  echo "  qmrestore /tmp/$(basename "$VMA_FILE") 100 --storage local-lvm"
else
  warn "Output tidak ditemukan di $OUTPUT_DIR/result"
  warn "Cek manual di: $OUTPUT_DIR"
  ls -la "$OUTPUT_DIR" 2>/dev/null || true
fi
