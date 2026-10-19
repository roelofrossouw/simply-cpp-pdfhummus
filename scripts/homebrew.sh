#!/bin/bash
#~~~~~~~~~~
# Writes the Homebrew formula simply-cpp-pdfhummus.rb for the PDF-Writer
# version in VERSION.txt: Homebrew has no PDFHummus of its own (unlike
# OpenCV, say), so macOS builds it from the upstream release tarball against
# Homebrew's FreeType, libjpeg, libpng, libtiff and OpenSSL.
#
# Usage: scripts/homebrew.sh [formula directory]
#   (default: the suite's homebrew/Formula when this module is in the suite)
#
# It only writes the file: committing and pushing the tap publishes it.

set -euo pipefail

scriptfile=$(realpath "$0")
scriptpath="${scriptfile%/*}"
dirpath=$(realpath "$scriptpath"/..)

suite=$(git -C "$dirpath" rev-parse --show-superproject-working-tree 2>/dev/null || true)
formula_dir="${1:-${suite:+$suite/homebrew/Formula}}"
if [ -z "$formula_dir" ] || [ ! -d "$formula_dir" ]; then
    echo "No formula directory: pass one, or run this inside the simply-cpp suite" >&2
    exit 1
fi

version=$(tr -d ' \t\n' < "$dirpath/VERSION.txt")
url="https://github.com/galkahana/PDF-Writer/archive/refs/tags/v$version.tar.gz"
echo "Hashing $url"
sha256=$(curl -fsSL "$url" | shasum -a 256 | cut -d' ' -f1)

cat > "$formula_dir/simply-cpp-pdfhummus.rb" <<EOF
class SimplyCppPdfhummus < Formula
  desc "PDFHummus (PDF-Writer) PDF library, as simply-cpp-pdf uses it"
  homepage "https://github.com/galkahana/PDF-Writer"
  url "$url"
  sha256 "$sha256"
  license "Apache-2.0"

  depends_on "cmake" => :build
  depends_on "freetype"
  depends_on "jpeg-turbo"
  depends_on "libpng"
  depends_on "libtiff"
  depends_on "openssl@3"
  uses_from_macos "zlib"

  # Our changes to upstream (the suite module's patches/), after __END__.
  patch :DATA

  def install
    # USE_UNBUNDLED_FALLBACK_BUNDLED only so it doesn't insist on a system libaesgm:
    # OpenSSL does its AES instead. Everything else comes from Homebrew.
    system "cmake", "-S", ".", "-B", "build",
           "-DBUILD_SHARED_LIBS=ON",
           "-DUSE_BUNDLED=FALSE",
           "-DUSE_UNBUNDLED_FALLBACK_BUNDLED=TRUE",
           *std_cmake_args
    system "cmake", "--build", "build", "--target", "PDFWriter"
    system "cmake", "--install", "build"
  end

  test do
    assert_path_exists lib/"cmake/PDFHummus/PDFHummusConfig.cmake"
    assert_path_exists include/"PDFWriter/PDFWriter.h"
  end
end
EOF
# The patches, which "patch :DATA" reads from after __END__.
{
    echo "__END__"
    cat "$scriptpath"/../patches/*.patch
} >> "$formula_dir/simply-cpp-pdfhummus.rb"
echo "Wrote $formula_dir/simply-cpp-pdfhummus.rb"
