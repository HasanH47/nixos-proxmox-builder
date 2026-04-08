# NixOS 25.11 Proxmox Image Builder

Build NixOS 25.11 Proxmox image (`.vma.zst`) menggunakan Nix lokal (tanpa Docker).

## Struktur File

```
.
├── Dockerfile         # (legacy) dulu dipakai untuk build via Docker
├── flake.nix          # Definisi build dengan nixpkgs 25.11
├── configuration.nix  # Konfigurasi NixOS untuk VM Proxmox
├── build.sh           # Script helper untuk build & output
└── output/            # Folder hasil build (dibuat otomatis)
```

## Cara Pakai

### 0. Install Nix

Pastikan Nix sudah terinstall dan tersedia di shell kamu.

Untuk zsh biasanya:
```bash
. ~/.nix-profile/etc/profile.d/nix.sh
nix --version
```

Opsional (mengurangi masalah koneksi HTTP/2 ke cache):
```bash
mkdir -p ~/.config/nix
cat > ~/.config/nix/nix.conf <<'EOF'
experimental-features = nix-command flakes
http2 = false
EOF
```

### 1. Tambahkan SSH public key kamu

Edit `configuration.nix`, cari bagian ini dan isi dengan SSH key kamu:

```nix
openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAAC3Nza... user@host"
];
```

Untuk lihat SSH key kamu:
```bash
cat ~/.ssh/id_ed25519.pub
# atau
cat ~/.ssh/id_rsa.pub
```

### 2. (Opsional) Sesuaikan konfigurasi VM

Di `configuration.nix`, kamu bisa ubah:
- `proxmox.qemuConf.cores` → jumlah CPU
- `proxmox.qemuConf.memory` → RAM dalam MB
- `virtualisation.diskSize` → ukuran disk (MiB). Contoh 20GiB = `20480`.
- `proxmox.qemuConf.bios` → `"seabios"` atau `"ovmf"` (UEFI)
- `time.timeZone` → timezone

### 3. Build

```bash
chmod +x build.sh
./build.sh qcow2
```

Kalau VM Proxmox kamu pakai BIOS legacy (SeaBIOS) dan QCOW2 UEFI stuck di
"Booting from Hard Disk…", build varian legacy:
```bash
./build.sh qcow2-bios
```

Atau manual tanpa script (perhatikan `#` harus di-quote di zsh):
```bash
mkdir -p output
nix build -L '.#qcow2-image' --out-link ./output/result
```

> **Catatan:** Build pertama bisa memakan waktu 15–45 menit karena
> download dari binary cache / build. Build berikutnya lebih cepat karena
> artefak tersimpan di `/nix/store`.

### 4. Copy ke Proxmox

```bash
scp output/result/*.qcow2 root@<proxmox-host>:/tmp/
```

### 5. Restore di Proxmox

SSH ke Proxmox, lalu:
```bash
qmrestore /tmp/vzdump-qemu-nixos-template.vma.zst 100 --storage local-lvm
```
Ganti `100` dengan VMID yang kamu inginkan.

### 6. Konfigurasi Cloud-init di Proxmox (opsional)

Setelah restore, kamu bisa set dari Proxmox UI:
- IP address / DHCP
- SSH public key
- Hostname

Atau via CLI:
```bash
qm set 100 --ciuser nixos --sshkeys ~/.ssh/id_ed25519.pub
qm set 100 --ipconfig0 ip=dhcp
```

### 7. Start VM & remote update

```bash
qm start 100

# Update konfigurasi remote (dari mesin kamu)
nixos-rebuild switch --flake .#namaHost \
  --target-host nixos@<ip-vm> \
  --use-remote-sudo
```

## Troubleshooting

**zsh: no matches found: .#proxmox-image**
Quote target flake:
```bash
nix build '.#proxmox-image'
```

**QCOW2 stuck "Booting from Hard Disk" di Proxmox**
QCOW2 default di repo ini adalah **UEFI**. Di Proxmox, pastikan VM pakai **OVMF/UEFI**
(dan Secure Boot dimatikan), atau build varian legacy:
```bash
./build.sh qcow2-bios
```

**VM tidak dapat IP setelah boot:**
Pastikan `proxmox.cloudInit.enable = true` dan `systemd.network.enable = true`
ada di `configuration.nix`, dan cloud-init drive sudah di-attach di Proxmox.

**Tidak bisa SSH setelah boot:**
Pastikan SSH public key sudah benar di `configuration.nix` sebelum build.
