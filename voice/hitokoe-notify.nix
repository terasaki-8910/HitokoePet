# NixOS 向けパッケージ定義（SPEC 3.3）。フックは最小限の環境で起動され PATH が
# 通っていない場合があるため、writeShellApplication の runtimeInputs で依存を閉じ込める。
# スクリプト本体はここに書かず voice/hitokoe-notify.sh を読み込む（二重管理を避ける）。
{ pkgs ? import <nixpkgs> { } }:

pkgs.writeShellApplication {
  name = "hitokoe-notify";
  text = builtins.readFile ./hitokoe-notify.sh;
  runtimeInputs = with pkgs; [
    coreutils # mkdir, rmdir, sha1sum, cat, cut, date, mv, rm, sed
    curl
    pipewire # pw-play
    pulseaudio # paplay
    ffmpeg # ffplay
    alsa-utils # aplay
  ];
}
