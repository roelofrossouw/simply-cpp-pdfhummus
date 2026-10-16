# simply-cpp-pdfhummus

PDFHummus ([PDF-Writer](https://github.com/galkahana/PDF-Writer), Apache-2.0),
built from source and repackaged for apt and Homebrew.

This exists so `simply-cpp-pdf` can link PDFHummus as a normal system library
instead of carrying its source. There's no code of ours here: it builds
PDFHummus as a shared library against the system's own zlib, FreeType,
libjpeg, libtiff, libpng and OpenSSL (none of PDFHummus's bundled copies; the
build fails if one creeps in) and packages the result.

## Install

```bash
sudo curl -fsSL https://apt.roelof.co.za/setup.sh | bash
sudo apt -y install simply-cpp-pdfhummus
```

On macOS:

```bash
brew install roelofrossouw/sc/simply-cpp-pdfhummus
```

This installs the headers to `include/PDFWriter`, the shared library
`libPDFWriter`, and PDFHummus's own `PDFHummusConfig.cmake`, so
`find_package(PDFHummus CONFIG REQUIRED)` and
`target_link_libraries(... PRIVATE PDFHummus::PDFWriter)` work as with any
other installed library. PDFHummus's CMake config looks for ZLIB, Freetype,
JPEG, TIFF, PNG and OpenSSL, so building against it also needs their `-dev`
packages (`simply-cpp-pdf-dev` depends on them).

## Publishing a new version

Like `simply-cpp-oatpp`, this compiles from source, so the result is tied
to whichever Ubuntu release built it: `scripts/deploy.sh` runs
`scripts/publish.sh` separately on jammy, noble and resolute. The package's
`Depends:` comes from `dpkg-shlibdeps`, since the library package names differ
between releases (`libtiff5`/`libtiff6`, `libssl3`/`libssl3t64`).

Bump `VERSION.txt` to the PDF-Writer tag to build (e.g. `4.9.1` for
[v4.9.1](https://github.com/galkahana/PDF-Writer/releases)), commit, then:

```bash
scripts/deploy.sh
```

`scripts/publish.sh --build-only`, run on a build server, builds the `.deb`
without publishing it, for trying a new version out.

For Homebrew, `scripts/homebrew.sh` rewrites the tap's
`Formula/simply-cpp-pdfhummus.rb` for the version in `VERSION.txt`; committing
and pushing the tap publishes it.
