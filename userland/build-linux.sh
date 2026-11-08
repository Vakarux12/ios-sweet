#!/bin/bash
# build.sh's outputs on linux, with clang + ld64.lld against an iphoneos 16.5 sdk (theos/sdks)
#   SDK=.../iPhoneOS16.5.sdk LLVM=dir with llvm-ar, llvm-nm, llvm-strip, llvm-install-name-tool
set -e
VERSION=25.0.7
SHA256=592272df3cf01e85e7db300c449df5061092574d099da275d19e97ef0510f8a6
ROOT=$(cd "$(dirname "$0")" && pwd)
B=$ROOT/build
O=$ROOT/out
SDK=${SDK:?set SDK to an iPhoneOS16.5.sdk}
LLVM=${LLVM:-/usr/bin}
mkdir -p "$B" "$O"
cd "$B"

[ -f mesa-$VERSION.tar.xz ] || curl -sL --fail -o mesa-$VERSION.tar.xz https://archive.mesa3d.org/mesa-$VERSION.tar.xz
echo "$SHA256  mesa-$VERSION.tar.xz" | sha256sum -c --quiet
rm -rf mesa-$VERSION build-mesa
tar xJf mesa-$VERSION.tar.xz
for p in "$ROOT"/mesa/*.patch; do patch -s --no-backup-if-mismatch -d mesa-$VERSION -p1 < "$p"; done
cp -r "$ROOT/mesa/redwood-drm" mesa-$VERSION/src/redwood-drm

[ -x venv/bin/python3 ] || { python3 -m venv venv && venv/bin/pip -q install meson==1.7.0 ninja mako pyyaml packaging; }
export PATH=$B/venv/bin:$PATH
T="'-target', 'arm64-apple-ios16.0', '-isysroot', '$SDK'"
cat > cross.ini <<INI
[binaries]
c = ['clang', $T]
cpp = ['clang++', $T, '-fuse-cxa-atexit']
objc = ['clang', $T]
ar = '$LLVM/llvm-ar'
ranlib = '$LLVM/llvm-ranlib'
strip = '$LLVM/llvm-strip'
c_ld = 'lld'
cpp_ld = 'lld'
objc_ld = 'lld'
pkg-config = 'false'

[built-in options]
c_link_args = ['-Wl,-adhoc_codesign']
cpp_link_args = ['-Wl,-adhoc_codesign']

[host_machine]
system = 'darwin'
subsystem = 'ios'
cpu_family = 'aarch64'
cpu = 'arm64'
endian = 'little'

[properties]
needs_exe_wrapper = true
INI
meson setup build-mesa mesa-$VERSION --cross-file cross.ini --wrap-mode=nofallback \
	--prefix=/topaz --libdir=lib --buildtype=release -Db_ndebug=true \
	-Dplatforms= -Dgallium-drivers=softpipe,freedreno -Dfreedreno-kmds=msm -Dvulkan-drivers= -Dglx=disabled -Degl=disabled -Dgbm=disabled \
	-Dosmesa=true -Dllvm=disabled -Dshared-glapi=enabled -Dgles1=disabled -Dgles2=enabled -Dopengl=true \
	-Dzstd=disabled -Dxmlconfig=disabled -Dexpat=disabled -Dshader-cache=disabled -Dvalgrind=disabled \
	-Dlibunwind=disabled -Dglvnd=disabled -Dvideo-codecs= -Dtools= -Dgallium-vdpau=disabled -Dgallium-va=disabled \
	-Dgallium-xa=disabled -Dlmsensors=disabled -Dbuild-tests=false
ninja -C build-mesa

"$LLVM/llvm-strip" -x -o "$O/libOSMesa.8.dylib" build-mesa/src/gallium/targets/osmesa/libOSMesa.8.dylib
"$LLVM/llvm-install-name-tool" -id /topaz/lib/libOSMesa.8.dylib "$O/libOSMesa.8.dylib"
"$LLVM/llvm-nm" -gU "$O/libOSMesa.8.dylib" | awk '$3 ~ /^_gl/ { print substr($3, 2) }' > exported-gl.txt
python3 "$ROOT/mkeagl.py" "$ROOT/eagl_slots.txt" mesa-$VERSION/src/mapi/glapi/registry/gl.xml exported-gl.txt \
	"$ROOT/gpu/eagl.c" > eagl_gen.h

DYN=(clang -target arm64-apple-ios16.0 -isysroot "$SDK" -fuse-ld=lld -Wl,-adhoc_codesign -O2)
"${DYN[@]}" -dynamiclib -install_name /topaz/lib/libtopaz-gl.dylib -I"$B" -framework CoreFoundation \
	-framework IOKit -framework IOSurface -lobjc "$O/libOSMesa.8.dylib" -o "$O/libtopaz-gl.dylib" \
	"$ROOT/gpu/eagl.c" "$ROOT/gpu/gl_osmesa.c"
"${DYN[@]}" -dynamiclib -install_name /topaz/lib/libtopaz-inject.dylib -framework CoreFoundation \
	-framework IOKit -lobjc -o "$O/libtopaz-inject.dylib" "$ROOT/gpu/topaz_inject.c"
mkdir -p "$O/RedwoodAudio.driver"
"${DYN[@]}" -bundle -framework CoreFoundation -o "$O/RedwoodAudio.driver/RedwoodAudio" "$ROOT/audio/audio_plugin.c"
cp "$ROOT/audio/audio_plugin.plist" "$O/RedwoodAudio.driver/Info.plist"
cd "$O" && sha256sum *.dylib RedwoodAudio.driver/* > SHA256SUMS && ls -l . RedwoodAudio.driver
