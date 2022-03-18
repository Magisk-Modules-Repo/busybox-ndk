## Busybox for Android NDK
### osm0sis @ xda-developers
*Static busybox binary for all Android architectures built with the NDK*

### Links
* [GitHub](https://github.com/Magisk-Modules-Repo/Busybox-Installer)
* [Support](https://bit.do/osm0)
* [Sponsor](https://github.com/sponsors/osm0sis)
* [Donate](https://www.paypal.me/osm0sis)

### Description
A byproduct of building my own busybox for my [AIK-mobile](https://bit.do/AIK_) package, I figured I might as well offer them separately since there weren't any providers making Android x64 builds.

Detects device (ARM/64, x86/_64, MIPS/64) to install the busybox binary, cleans up symlinks from any previous install and generates new ones. Detects and supports SuperSU/Magisk systemless installs.

My build configs/patches are available here: [android-busybox-ndk](https://github.com/osm0sis/android-busybox-ndk)

Please read the [release post](https://bit.do/BBNDK) for more info about applet inclusion, zip renaming options and special features.
