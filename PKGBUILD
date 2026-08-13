# Maintainer: Tobi Lutke <tobi@shopify.com>
pkgname=try-cli
pkgver=1.10.1
pkgrel=1
pkgdesc="Fresh directories for every vibe (native Spinel binary)"
arch=('x86_64')
url="https://github.com/tobi/try"
license=('MIT')
depends=('glibc' 'libxcrypt')
provides=('try')
conflicts=('try')
source=("$pkgname-$pkgver-x86_64.tar.gz::https://github.com/tobi/try/releases/download/v$pkgver/try-linux-x86_64.tar.gz")
sha256sums=('SKIP')

package() {
    install -Dm755 try "$pkgdir/usr/bin/try"
}
