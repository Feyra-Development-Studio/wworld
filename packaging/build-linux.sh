#!/usr/bin/env bash
# Сборка бинарников и пакетов deb/rpm для Linux.
#   packaging/build-linux.sh <версия> [каталог назначения]
# Требует: fpc, dpkg-deb, rpmbuild.
set -euo pipefail

VERSION="${1:?нужна версия, например 0.1.0}"
DIST="${2:-dist}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

rm -rf build/linux "$DIST"
mkdir -p build/linux/units "$DIST"

echo "== сборка бинарников =="
fpc -Mobjfpc -Sh -O2 -Fusrc/dungeon -FUbuild/linux/units \
    -obuild/linux/wworld src/demo/demo.pas > /dev/null
fpc -Mobjfpc -Sh -O2 -Fusrc/dungeon -FUbuild/linux/units \
    -obuild/linux/wworld-walk src/demo/wwwalk.pas > /dev/null
strip build/linux/wworld build/linux/wworld-walk

echo "== раскладка =="
PKG=build/linux/pkgroot
mkdir -p "$PKG/usr/bin" "$PKG/usr/share/wworld" "$PKG/usr/share/doc/wworld"
install -m 0755 build/linux/wworld build/linux/wworld-walk "$PKG/usr/bin/"
install -m 0644 scripts/geometry.R scripts/validate_dungeon.R "$PKG/usr/share/wworld/"
install -m 0644 README.md "$PKG/usr/share/doc/wworld/"

echo "== deb =="
mkdir -p "$PKG/DEBIAN"
cat > "$PKG/DEBIAN/control" <<EOF
Package: wworld
Version: $VERSION
Section: games
Priority: optional
Architecture: amd64
Depends: r-base-core | r-base
Recommends: r-cran-codetools
Maintainer: Risto90 <2493131+Risto90@users.noreply.github.com>
Description: Генератор подземелий wworld
 Строит подземелье из комнат разной формы, соединённых коридорами трёх
 рангов, и хранит его графом-инструкцией в JSON. Геометрию и топологию
 карты считает R, поэтому пакету нужен Rscript.
EOF
dpkg-deb --build --root-owner-group "$PKG" "$DIST/wworld_${VERSION}_amd64.deb" > /dev/null

echo "== rpm =="
RPMTOP=build/linux/rpm
mkdir -p "$RPMTOP"/{BUILD,RPMS,SOURCES,SPECS,SRPMS,BUILDROOT}
cat > "$RPMTOP/SPECS/wworld.spec" <<EOF
%global _build_id_links none
%global debug_package %{nil}
Name:           wworld
Version:        $VERSION
Release:        1
Summary:        Генератор подземелий wworld
License:        GPLv3
BuildArch:      x86_64
Requires:       R-core

%description
Строит подземелье из комнат разной формы, соединённых коридорами трёх
рангов, и хранит его графом-инструкцией в JSON. Геометрию и топологию
карты считает R, поэтому пакету нужен Rscript.

%install
mkdir -p %{buildroot}/usr/bin %{buildroot}/usr/share/wworld %{buildroot}/usr/share/doc/wworld
install -m 0755 $ROOT/build/linux/wworld %{buildroot}/usr/bin/wworld
install -m 0755 $ROOT/build/linux/wworld-walk %{buildroot}/usr/bin/wworld-walk
install -m 0644 $ROOT/scripts/geometry.R %{buildroot}/usr/share/wworld/geometry.R
install -m 0644 $ROOT/scripts/validate_dungeon.R %{buildroot}/usr/share/wworld/validate_dungeon.R
install -m 0644 $ROOT/README.md %{buildroot}/usr/share/doc/wworld/README.md

%files
/usr/bin/wworld
/usr/bin/wworld-walk
/usr/share/wworld/geometry.R
/usr/share/wworld/validate_dungeon.R
/usr/share/doc/wworld/README.md
EOF
rpmbuild --define "_topdir $ROOT/$RPMTOP" -bb "$RPMTOP/SPECS/wworld.spec" > /dev/null
cp "$RPMTOP"/RPMS/x86_64/wworld-*.rpm "$DIST/"

echo "== готово =="
ls -1sh "$DIST"
