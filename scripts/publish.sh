#!/bin/bash
#~~~~~~~~~~
# Builds PDFHummus (github.com/galkahana/PDF-Writer, Apache-2.0) from source
# as a shared library against Ubuntu's own zlib, FreeType, libjpeg, libtiff,
# libpng and OpenSSL (none of PDFHummus's bundled copies), and packages and
# publishes it as simply-cpp-pdfhummus for apt.
#
# Like simply-cpp-oatpp this is a real compile, so the result is tied to
# whichever Ubuntu release built it - run this separately on each distro's own
# server (deploy.sh does that).
#
# Run this in the directory deploy.sh synced it to (/var/www/build/sc-pdfhummus).
#
# Usage: scripts/publish.sh [--build-only]
#   --build-only  builds the .deb but doesn't publish it (for trying a new version out)

set -euo pipefail

build_only=""
if [ "${1:-}" = "--build-only" ]; then
    build_only=1
fi

version=$(tr -d ' \t\n' < VERSION.txt)
ubuntu_codename=$(lsb_release -sc)
package="simply-cpp-pdfhummus"
# A packaging revision (REVISION.txt) when the same upstream version is packaged again, such as
# with a copyright file: 3.5.0-1~noble sorts after 3.5.0~noble.
revision=$( [ -f REVISION.txt ] && tr -d ' \t\n' < REVISION.txt || true)
package_version="${version}${revision:+-$revision}~${ubuntu_codename}"
deb_file="${package}_${package_version}_amd64.deb"

# dpkg-dev for dpkg-shlibdeps, which works out the runtime Depends: below.
apt -y install cmake g++ git dpkg-dev \
    zlib1g-dev libfreetype-dev libjpeg-dev libtiff-dev libpng-dev libssl-dev >/dev/null

rm -rf pkg work/build work/shlibdeps
mkdir -p pkg/DEBIAN

if [ ! -d "work/pdfhummus-src" ] || [ "$(git -C work/pdfhummus-src describe --tags 2>/dev/null)" != "v$version" ]; then
    rm -rf work/pdfhummus-src
    echo "Cloning PDF-Writer v$version"
    git clone --branch "v$version" --depth 1 https://github.com/galkahana/PDF-Writer.git work/pdfhummus-src
fi
# Our changes to upstream (patches/, in order), on a clean checkout each time.
git -C work/pdfhummus-src checkout -q -- .
for patch in patches/*.patch; do
    [ -f "$patch" ] || continue
    echo "Applying $patch"
    git -C work/pdfhummus-src apply "$(pwd)/$patch" || exit 1
done

# USE_UNBUNDLED_FALLBACK_BUNDLED only so PDFHummus doesn't insist on a system
# libaesgm: OpenSSL does its AES instead. The check after the install makes
# sure nothing else fell back to a bundled copy.
cmake -S work/pdfhummus-src -B work/build \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=ON \
    -DUSE_BUNDLED=FALSE \
    -DUSE_UNBUNDLED_FALLBACK_BUNDLED=TRUE
cmake --build work/build -j"$(nproc)" --target PDFWriter
DESTDIR="$(pwd)/pkg" cmake --install work/build --prefix /usr

bundled=$(find pkg/usr/lib -maxdepth 1 \( -name '*.so*' -o -name '*.a' \) ! -name 'libPDFWriter.so*' -print)
if [ -n "$bundled" ]; then
    echo "PDFHummus fell back to bundled libraries instead of Ubuntu's:" >&2
    echo "$bundled" >&2
    exit 1
fi

# The runtime libraries PDFWriter links (libfreetype6, libjpeg8, libtiff5/6, ...: the names differ
# between releases), as dpkg-shlibdeps finds them.
mkdir -p work/shlibdeps/debian
printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "$package" "$package" > work/shlibdeps/debian/control
library=$(realpath pkg/usr/lib/libPDFWriter.so)
depends=$(cd work/shlibdeps && dpkg-shlibdeps -O "$library" | sed -n 's/^shlibs:Depends=//p')

cat > pkg/DEBIAN/control <<EOF
Package: $package
Version: $package_version
Architecture: amd64
Section: libs
Priority: optional
Maintainer: Roelof Rossouw
Depends: $depends
Description: PDFHummus (PDF-Writer), repackaged for apt
 PDF creation library used by simply-cpp-pdf, built from upstream source
 (github.com/galkahana/PDF-Writer, Apache-2.0) as a shared library against
 the system's zlib, FreeType, libjpeg, libtiff, libpng and OpenSSL, so it can
 be installed like any other system dependency.
EOF

cat > pkg/DEBIAN/postinst <<'EOF'
#!/bin/sh
set -e
ldconfig
EOF

cat > pkg/DEBIAN/postrm <<'EOF'
#!/bin/sh
set -e
ldconfig
EOF

chmod 755 pkg/DEBIAN/postinst pkg/DEBIAN/postrm

# copyright <package directory> <package name>: upstream's licence, which it asks to ship with the
# binaries, where Debian keeps one (/usr/share/doc/<package>/copyright).
copyright() {
    install -d "$1/usr/share/doc/$2"
    {
        echo "$2 packages PDFHummus (PDF-Writer) $version (https://github.com/galkahana/PDF-Writer), licensed under Apache-2.0."
        echo "The packaging scripts (https://github.com/roelofrossouw/simply-cpp-pdfhummus) are Apache-2.0."
        echo
        echo "----- PDFHummus: LICENSE -----"
        cat work/pdfhummus-src/LICENSE
    } > "$1/usr/share/doc/$2/copyright"
}
copyright pkg "$package"

dpkg-deb --build --root-owner-group pkg "$deb_file"
dpkg-deb --field "$deb_file" Depends

if [ -n "$build_only" ]; then
    echo "Built $deb_file (not published)."
    exit 0
fi

pushd /var/www/build/repo >/dev/null
export GNUPGHOME=/var/www/build/signing
if reprepro list "$ubuntu_codename" | grep -q "$package .*$package_version"; then
    echo "$ubuntu_codename: $package $package_version already published"
else
    echo "$ubuntu_codename: publishing $package $package_version"
    reprepro remove "$ubuntu_codename" "$package" || true
    reprepro includedeb "$ubuntu_codename" "/var/www/build/sc-pdfhummus/$deb_file"
fi
popd >/dev/null

echo "Done."
