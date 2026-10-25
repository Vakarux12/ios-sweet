#!/bin/bash
# opengl es for backboardd, built on a mac with xcode (ci: .github/workflows/userland.yml)
#   out/libOSMesa.8.dylib      mesa 25.0.7 freedreno + softpipe behind osmesa
#   out/libtopaz-gl.dylib      eagl.c, the EAGLContext coreanimation draws with
#   out/libtopaz-inject.dylib  loads libtopaz-gl in backboardd when RedwoodGPU is up
#   out/RedwoodAudio.driver    hal plug-in for mediaserverd, its "Actuator" feeds /dev/redwood-haptic
# all go to /topaz/lib on the phone, boot-arg topaz_inject=/topaz/lib/libtopaz-inject.dylib,backboardd
set -e
VERSION=25.0.7
SHA256=592272df3cf01e85e7db300c449df5061092574d099da275d19e97ef0510f8a6
ROOT=$(cd "$(dirname "$0")" && pwd)
B=$ROOT/build
O=$ROOT/out
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CC=$(xcrun --sdk iphoneos -f clang)
mkdir -p "$B" "$O"
cd "$B"

[ -f mesa-$VERSION.tar.xz ] || curl -sL --fail -o mesa-$VERSION.tar.xz https://archive.mesa3d.org/mesa-$VERSION.tar.xz
echo "$SHA256  mesa-$VERSION.tar.xz" | shasum -a 256 -c --quiet
rm -rf mesa-$VERSION build-mesa
tar xJf mesa-$VERSION.tar.xz
for p in "$ROOT"/mesa/*.patch; do patch -s --no-backup-if-mismatch -d mesa-$VERSION -p1 < "$p"; done
cp -r "$ROOT/mesa/redwood-drm" mesa-$VERSION/src/redwood-drm

[ -x venv/bin/python3 ] || { python3 -m venv venv && venv/bin/pip -q install meson==1.7.0 ninja mako pyyaml packaging; }
# mesa wants a newer bison than /usr/bin has
export PATH=$B/venv/bin:/opt/homebrew/opt/bison/bin:/usr/local/opt/bison/bin:$PATH
cat > cross.ini <<INI
[binaries]
c = ['$CC', '-target', 'arm64-apple-ios16.0', '-isysroot', '$SDK']
cpp = ['$CC++', '-target', 'arm64-apple-ios16.0', '-isysroot', '$SDK', '-fuse-cxa-atexit']
objc = ['$CC', '-target', 'arm64-apple-ios16.0', '-isysroot', '$SDK']
ar = '$(xcrun -f ar)'
ranlib = '$(xcrun -f ranlib)'
strip = '$(xcrun -f strip)'
pkg-config = 'false'

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

$(xcrun -f strip) -x -o "$O/libOSMesa.8.dylib" build-mesa/src/gallium/targets/osmesa/libOSMesa.8.dylib
install_name_tool -id /topaz/lib/libOSMesa.8.dylib "$O/libOSMesa.8.dylib"
nm -gU "$O/libOSMesa.8.dylib" | awk '$3 ~ /^_gl/ { print substr($3, 2) }' > exported-gl.txt
python3 "$ROOT/mkeagl.py" "$ROOT/eagl_slots.txt" mesa-$VERSION/src/mapi/glapi/registry/gl.xml exported-gl.txt \
	"$ROOT/gpu/eagl.c" > eagl_gen.h

DYN=("$CC" -target arm64-apple-ios16.0 -isysroot "$SDK" -O1)
"${DYN[@]}" -dynamiclib -install_name /topaz/lib/libtopaz-gl.dylib -I"$B" -framework CoreFoundation \
	-framework IOKit -framework IOSurface -lobjc "$O/libOSMesa.8.dylib" -o "$O/libtopaz-gl.dylib" \
	"$ROOT/gpu/eagl.c" "$ROOT/gpu/gl_osmesa.c"
"${DYN[@]}" -dynamiclib -install_name /topaz/lib/libtopaz-inject.dylib -framework CoreFoundation \
	-framework IOKit -lobjc -o "$O/libtopaz-inject.dylib" "$ROOT/gpu/topaz_inject.c"
mkdir -p "$O/RedwoodAudio.driver"
"${DYN[@]}" -bundle -framework CoreFoundation -o "$O/RedwoodAudio.driver/RedwoodAudio" "$ROOT/audio/audio_plugin.c"
cp "$ROOT/audio/audio_plugin.plist" "$O/RedwoodAudio.driver/Info.plist"
# install_name_tool broke the linker signature
codesign -f -s - "$O"/*.dylib "$O/RedwoodAudio.driver/RedwoodAudio"
cd "$O" && shasum -a 256 *.dylib RedwoodAudio.driver/* > SHA256SUMS && ls -l . RedwoodAudio.driver
