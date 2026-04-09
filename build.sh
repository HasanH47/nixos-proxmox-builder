#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# NixOS 25.11 Proxmox Image Builder
# Jalankan di Linux apapun + Nix (tanpa Docker)
# ============================================================

OUTPUT_DIR="$(pwd)/output"

# Nix builds can create large temp files; /tmp might be small (tmpfs).
export TMPDIR="${TMPDIR:-/var/tmp}"

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

# --- Cek SSH public key (configuration.nix atau modules/openssh-bootstrap.nix) ---
shopt -s nullglob
SSH_KEY_FOUND=0
for f in configuration.nix modules/*.nix; do
  [[ -f "$f" ]] || continue
  if grep -qE '"ssh-(rsa|ed25519|ecdsa|sk-ed25519|sk-ecdsa)' "$f" 2>/dev/null \
     || grep -qE 'sk-ssh-ed25519@openssh\.com' "$f" 2>/dev/null; then
    SSH_KEY_FOUND=1
    break
  fi
done
shopt -u nullglob
if [[ "$SSH_KEY_FOUND" -eq 0 ]]; then
  warn "Belum ada baris authorizedKeys yang berisi public key (ssh-ed25519 / ssh-rsa, dll.)"
  warn "Tambahkan di modules/openssh-bootstrap.nix atau override di configuration.nix"
  echo ""
  read -rp "Lanjut build tanpa SSH key? (y/N): " yn
  [[ "$yn" =~ ^[Yy]$ ]] || exit 0
fi

# --- Buat output dir ---
mkdir -p "$OUTPUT_DIR"

info "Jalankan build NixOS 25.11 Proxmox image..."
info "Ini akan memakan waktu cukup lama (15-45 menit tergantung koneksi & CPU)"
echo ""

FORMAT="${1:-qcow2-universal}"

case "$FORMAT" in
  qcow2-universal|qcow2|qcow2-bios|proxmox)
    ;;
  *)
    error "Format tidak dikenali: $FORMAT (pilih: qcow2-universal | qcow2 | qcow2-bios | proxmox)"
    ;;
esac

OUT_LINK="$OUTPUT_DIR/result"
rm -f "$OUT_LINK" 2>/dev/null || true

# zsh akan melakukan globbing pada `#` kalau tidak di-quote.
TARGET='.#qcow2-universal-image'
if [[ "$FORMAT" == "qcow2" ]]; then
  TARGET='.#qcow2-image'
elif [[ "$FORMAT" == "qcow2-bios" ]]; then
  TARGET='.#qcow2-bios-image'
elif [[ "$FORMAT" == "proxmox" ]]; then
  TARGET='.#proxmox-image'
fi

# zsh akan melakukan globbing pada `#` kalau tidak di-quote.
nix build -L "$TARGET" --out-link "$OUT_LINK"

# --- Cari file VMA hasil build ---
VMA_FILE=$(find -L "$OUTPUT_DIR/result" -maxdepth 2 -name "*.vma.zst" 2>/dev/null | head -1)
QCOW2_FILE=$(find -L "$OUTPUT_DIR/result" -maxdepth 2 -name "*.qcow2" 2>/dev/null | head -1)

if [[ -z "$VMA_FILE" ]]; then
  # Coba cari di dalam output lain kalau user ubah out-link manual.
  VMA_FILE=$(find -L "$OUTPUT_DIR" -name "*.vma.zst" 2>/dev/null | head -1)
fi

echo ""
info "============================================"
info "Build selesai!"
info "============================================"

if [[ "$FORMAT" == qcow2* && -n "$QCOW2_FILE" ]]; then
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
