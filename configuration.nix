# Thin entrypoint: ubah opsi `image.*` di sini atau tambah modul sendiri.
{ ... }:

{
  imports = [ ./modules/default.nix ];

  # Contoh profil lebih ketat setelah bootstrap:
  # image.ssh.allowPasswordAuth = false;
  # image.security.sudoNopasswdForSudoGroup = false;
  #
  # Lab tanpa ISO cloud-init (ping tanpa metadata):
  # image.cloudInit.allowFallbackDhcp = true;
}
