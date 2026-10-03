# Maintainer: Zephyrine Shell Authors
pkgname=zephyrine-shell-git
pkgver=1.0.0
pkgrel=1
pkgdesc="Modern, elegant Wayland desktop shell based on Hyprland and Quickshell"
arch=('any')
url="https://github.com/rzalevsky/zephyrine-shell"
license=('MIT')
depends=(
    'hyprland'
    'quickshell'
    'mpvpaper'
    'socat'
    'jq'
    'python'
    'qt6ct'
    'papirus-icon-theme'
    'adw-gtk-theme'
    'wireplumber'
    'brightnessctl'
    'playerctl'
    'hypridle'
    'hyprlock'
    'hyprpolkitagent'
    'xdg-desktop-portal'
    'xdg-desktop-portal-hyprland'
    'gnome-keyring'
    'ttf-jetbrains-mono-nerd'
    'lua'
)
optdepends=(
    'networkmanager: Wi-Fi management and network monitoring'
    'bluez: Bluetooth service'
    'bluez-utils: Bluetooth management CLI and pairing agent'
    'power-profiles-daemon: power profiles switcher'
    'grim: screen capture utility'
    'slurp: region selector for screenshots'
    'satty: screenshot annotation tool'
    'ffmpeg: video wallpaper thumbnail generator'
    'wl-clipboard: clipboard utilities for palette hex colors'
    'libnotify: desktop notifications helper'
    'sddm: recommended display manager for Zephyrine login theme'
    'kitty: default terminal with matching Zephyrine palette'
    'thunar: default file manager'
    'zed: editor with matching Zephyrine theme'
    'zathura: document viewer'
    'zathura-pdf-mupdf: PDF support for zathura'
)
provides=('zephyrine-shell')
conflicts=('zephyrine-shell')
source=("git+file://${PWD}")
sha256sums=('SKIP')

package() {
    cd "${srcdir}/${pkgname}" 2>/dev/null || cd "${srcdir}/.."
    make DESTDIR="${pkgdir}" PREFIX=/usr install
    install -Dm644 LICENSE "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE" 2>/dev/null || true
}
