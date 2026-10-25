#!/bin/bash
# Build the SWEET kernel on a local Mac the same way .github/workflows/xnu.yml does.
#   xnu/build-mac.sh WORKDIR [incr]   -> WORKDIR/out/kernel.development.sweet + SHA256SUMS
# incr keeps the last tree: build.sh skips patches that no longer apply (already in) and
# steps whose output exists, so only new patches get applied and make rebuilds what changed.
# an edited old patch is skipped too (only a warning), that needs a full build.
# Needs Xcode 15.x at /Applications/Xcode_15.4.app (its iig matches xnu-8796, 16+ does not),
# brew jq gum bash cmake ninja, a stub xcodes on PATH, the 13.5 KDK (build.sh fetches it with sudo).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$1
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode_15.4.app/Contents/Developer}
export PATH=/usr/local/bin:/opt/homebrew/bin:$PATH
export MACOS_VERSION=13.5 KERNEL_CONFIG=DEVELOPMENT MACHINE_CONFIG=SWEET
mkdir -p "$work"
cd "$work"
if [ "${2:-}" = incr ] && [ -d dxb/build/xnu.obj ]; then
	# the stage scripts already ran and refuse a second run
	rm -f dxb/build/xnu.obj/kernel.* dxb/patches/*.sh
	cp "$here"/patches/*.patch dxb/patches/
else
	rm -rf dxb
	git init -q dxb
	git -C dxb fetch -q --depth 1 https://github.com/blacktop/darwin-xnu-build 663906528d1cd5ea8fde7de6f16de73db9511549
	git -C dxb checkout -q FETCH_HEAD
	# libfirehose_kernel is built arm64e-only, the SWEET kernel is plain arm64
	sed -i '' 's/ARCHS="x86_64 arm64e" VALID_ARCHS="x86_64 arm64e"/ARCHS="x86_64 arm64e arm64" VALID_ARCHS="x86_64 arm64e arm64"/' dxb/build.sh
	cp "$here"/patches/*.patch "$here"/patches/*.sh dxb/patches/
fi
(cd dxb && bash build.sh)
rm -rf out && mkdir out
cp -R dxb/fakeroot/System/Library/Kernels/. out/
cd out && shasum -a 256 kernel.development.sweet > SHA256SUMS && cat SHA256SUMS
