# NixOS 25.11 Proxmox Image Builder

Build NixOS 25.11 image untuk Proxmox/QEMU menggunakan Nix lokal (tanpa Docker).
Default output sekarang adalah **1 QCOW2 universal** yang bisa boot di **BIOS (SeaBIOS)** maupun **UEFI (non–Secure Boot)**.

## Struktur File

```
.
├── Dockerfile         # (legacy) dulu dipakai untuk build via Docker
├── flake.nix          # Definisi build dengan nixpkgs 25.11
├── configuration.nix  # Konfigurasi NixOS untuk VM Proxmox
├── build.sh           # Script helper untuk build & output
├── scripts/           # Utilitas (simulasi QEMU mirip Proxmox)
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
users.users.nixos.openssh.authorizedKeys.keys = [
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

QCOW2 universal (BIOS + UEFI) (default):
```bash
./build.sh
# atau eksplisit:
./build.sh qcow2-universal
```

Atau manual tanpa script (perhatikan `#` harus di-quote di zsh):
```bash
mkdir -p output
nix build -L '.#qcow2-universal-image' --out-link ./output/result
```

> **Catatan:** Build pertama bisa memakan waktu 15–45 menit karena
> download dari binary cache / build. Build berikutnya lebih cepat karena
> artefak tersimpan di `/nix/store`.

### 4. Copy ke Proxmox

```bash
scp output/result/*.qcow2 root@<proxmox-host>:/tmp/
```

### 5. Import ke Proxmox (QCOW2)

SSH ke Proxmox, lalu (contoh VMID=100 dan storage `local-lvm`):
```bash
qm create 100 --name nixos-template --memory 2048 --cores 2 --bios seabios --net0 virtio,bridge=vmbr0
qm importdisk 100 /tmp/nixos-template.qcow2 local-lvm
qm set 100 --scsihw virtio-scsi-single --scsi0 local-lvm:vm-100-disk-0
qm set 100 --boot order=scsi0
qm start 100
```
Jika kamu pakai UEFI/OVMF, ganti `--bios seabios` menjadi `--bios ovmf` dan pastikan Secure Boot dimatikan.

Image template menyimpan password bootstrap user `nixos` di `configuration.nix`
(`initialPassword`, default build: login konsol **nixos / nixos**).
Ganti atau hapus password itu setelah SSH(key) dari cloud-init atau dari `configuration.nix` sudah dipakai.

### 6. Konfigurasi Cloud-init di Proxmox (disarankan)

Cloud-init dari Proxmox adalah **ISO NoCloud** (biasanya drive `ide2`, media CDROM), terpisah dari disk QCOW2 utama.

Checklist:

- Di UI: tab **Cloud-Init** — isi user (mis. `nixos`), SSH public key, IP/hostname sesuai kebutuhan lalu klik **Regenerate Image** agar seed ISO dibuat ulang.
- Pastikan VM punya **Cloud-Init drive** (bukan hanya disk import); tanpa itu metadata tidak masuk.
- `configuration.nix` mematikan DHCP “global” NixOS saat cloud-init aktif, agar jaringan ditulis dari user-data (sama seperti modul VMA `proxmox-image.nix` di nixpkgs).

Atau via CLI:
```bash
qm set 100 --ciuser nixos --sshkeys ~/.ssh/id_ed25519.pub
qm set 100 --ipconfig0 ip=dhcp
```

Verifikasi di guest setelah boot:

```bash
journalctl -u cloud-init-local -u cloud-init -u cloud-config -u cloud-final --no-pager
```

### 7. Start VM & remote update

```bash
qm start 100

# Update konfigurasi remote (dari mesin kamu)
nixos-rebuild switch --flake .#namaHost \
  --target-host nixos@<ip-vm> \
  --use-remote-sudo
```

## Uji lokal mirip Proxmox (QEMU: `scsi0` + NoCloud)

Kenapa dulu **ping bisa** tapi cloud-init terasa “tidak jalan”? DHCP dan route bisa tercukupi oleh **networking bawaan NixOS** (`useDHCP`) sementara **metadata NoCloud** (SSH key, hostname, user-data lain) tetap belum diproses dengan bersih. Template sekarang mematikan DHCP global saat cloud-init aktif supaya jaringan diserahkan ke **user-data** — jadi uji end-to-end pakai seed NoCloud lebih representatif.

Skrip berikut mem-boot QCOW2 dengan:

- disk root di **VirtIO SCSI** (`virtio-scsi-pci` + `scsi-hd`), setara disk di **`scsi0`** di Proxmox;
- **ISO NoCloud** terpisah (volume `cidata`), mirip drive cloud-init Proxmox;
- user-mode networking + **hostfwd SSH `localhost:2222` → guest :22**;
- konsol di **serial** (stdio).

Dependency untuk membuat ISO: **`xorriso`** (disarankan) atau `genisoimage`.

```bash
chmod +x scripts/qemu-proxmox-like-test.sh

# Pakai QCOW2 hasil build (sesuaikan path)
# Di zsh wajib quote 'nixpkgs#...' agar # tidak dibaca sebagai glob.
nix shell 'nixpkgs#xorriso' 'nixpkgs#qemu' -c \
  ./scripts/qemu-proxmox-like-test.sh ./output/result/nixos-template.qcow2
```

Opsional: `TEST_SSH_PUB=/path/ke/id_ed25519.pub` bila tidak pakai default `~/.ssh/id_ed25519.pub`.  
UEFI: `QEMU_UEFI=1` (butuh firmware OVMF di host; set `QEMU_OVMF_CODE` / `QEMU_OVMF_VARS` jika perlu).

Jika path QCOW menunjuk ke **`/nix/store/...`** (mis. lewat symlink `output/result`), QEMU biasanya butuh akses **tulis** ke berkas image; skrip otomatis membuat **overlay** di direktori temporary. Anda tetap perlu bisa **membaca** backing di store (bila SELinux memblokir, salin QCOW ke `~/` atau `/tmp` dulu).

Di host lain: `ssh -p 2222 nixos@127.0.0.1` (kunci harus cocok dengan yang dimasukkan skrip). Untuk keluar dari QEMU (`serial mon:stdio`): **Ctrl+a** kemudian **x**.

## Troubleshooting

**zsh: no matches found: .#proxmox-image**
Quote target flake:
```bash
nix build '.#proxmox-image'
```

**zsh: no matches found: nixpkgs#xorriso** (atau paket flake lain dengan `#`)
Quote tiap referensi, misalnya:
```bash
nix shell 'nixpkgs#xorriso' 'nixpkgs#qemu' -c ./scripts/qemu-proxmox-like-test.sh ./output/result/nixos-template.qcow2
```

**QCOW2 stuck "Booting from Hard Disk" di Proxmox**
QCOW2 default di repo ini adalah **UEFI**. Di Proxmox, pastikan VM pakai **OVMF/UEFI**
(dan Secure Boot dimatikan), atau build varian legacy:
```bash
./build.sh qcow2-bios
```

**QCOW2 universal untuk berbagai controller (`scsi0` / `virtio0`)**
Gunakan default `./build.sh` (target `qcow2-universal`) agar root mount portable (by-partuuid) dan bisa boot di BIOS/UEFI.

**Boot `scsi0` masih gagal (stuck initrd / root mount):**
Di Proxmox, utamakan **VirtIO SCSI** dengan profil **virtio-scsi-single** (atau `qm set ... --scsihw virtio-scsi-single`). Image sudah menyertakan modul initrd `scsi_mod` + `virtio_scsi` + `sd_mod`; jika masih bermasalah, cek serial/console VM untuk pesan modul atau `lsmod` setelah boot rescue.

**Cloud-init dari Proxmox tidak terbaca / tidak ada IP atau SSH key:**
Pastikan drive cloud-init ada, tab Cloud-Init diisi, dan **Regenerate Image** dijalankan. Lihat checklist di bagian 6 di atas.

**VM tidak dapat IP setelah boot:**
Pastikan `services.cloud-init` + `systemd.network.enable` aktif di `configuration.nix`, cloud-init drive terpasang, dan tidak ada bentrok DHCP (template ini memakai pola Proxmox: DHCP global NixOS off saat cloud-init on).

**Tidak bisa SSH setelah boot:**
SSH **password** dimatikan; pakai kunci yang di-build di `configuration.nix` atau yang di-inject Proxmox (`--sshkeys`). Konsol bisa dipakai dengan user **nixos** dan password bootstrap dari `initialPassword` sampai kunci siap.

**Bukan login standar Ubuntu:** user `nixos` tidak punya password bawaan kecuali `initialPassword` di `configuration.nix` (lihat bagian import / 6).
