# GL userland

CoreAnimation in backboardd draws with OpenGL ES through Mesa freedreno on the Adreno 618.
Kernel side: patch 0093 (RedwoodGPU on top of the shim's ring, boot-args `a71gpu=4 gpu=1`).

Build on a Mac with Xcode, or in CI (`gh workflow run userland.yml`, artifact `userland-gl`):

```
userland/build.sh   # -> userland/out
```

On the phone everything in `out/` goes to `/topaz/lib`, and the boot-args get
`topaz_inject=/topaz/lib/libtopaz-inject.dylib,backboardd`. `gl=0` keeps the software renderer.

## Sources

| Here | From |
|---|---|
| `gpu/eagl.c`, `gpu/gl_osmesa.c`, `gpu/redwood_gl.h`, `gpu/topaz_inject.c`, `mesa/osmesa-es-profile.patch`, `mesa/redwood-drm/` | [ios-topaz](https://github.com/MakrSas/ios-topaz) `userland/` (cache addresses for iOS 16.7.16 iPhone10,3) |
| `mkeagl.py`, `eagl_slots.txt`, `mesa/freedreno-darwin.patch` | [HackiOS userland](https://github.com/oosexgang/hackios-xnu-userland) |

All of it derives from HackiOS user space, MIT, Copyright (c) 2026 OOSEX GANG, see `LICENSE`.
