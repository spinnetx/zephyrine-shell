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
    'quickshell-git'
    'mpvpaper'
    'socat'
    'jq'
    'python'
    'qt6ct'
    'papirus-icon-theme'
)
optdepends=(
    'sddm: recommended display manager for Zephyrine login theme'
    'kitty: default terminal with matching Zephyrine palette'
    'thunar: default file manager'
    'zed: editor with matching Zephyrine theme'
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
