# Busybox for Android NDK
### osm0sis @ xda-developers
*Static busybox binary for all Android architectures built with the NDK*

### Links
* [GitHub](https://github.com/Magisk-Modules-Repo/Busybox-Installer)
* [Support](https://forum.xda-developers.com/showthread.php?t=2239421)
* [Donate](https://forum.xda-developers.com/donatetome.php?u=4544860)

### Description
As a byproduct of building my own static busybox compiles in all supported Android architectures for my [AIK-mobile](https://forum.xda-developers.com/showthread.php?t=2073775) package I figured I might as well offer them up separately as well since there weren't any providers making Android x64 builds when I was researching.

The installer detects what architecture (ARM/ARM64, x86/x86_64, MIPS/MIPS64) your device uses and installs the correct busybox binary accordingly. It then cleans up any symlinks from a possible previous installation in the same directory and generates new symlinks directly from the output of the installed binary. Using the zip name (also reading from /data/.busybox-ndk) to allow user choice, "nolinks" may be specified to opt out of symlink creation. Detects and supports "systemless" root via SuperSU/Magisk installation as well.

My busybox configs and patches are available here: [android-busybox-ndk](https://github.com/osm0sis/android-busybox-ndk)

Please read the [release post](https://forum.xda-developers.com/showpost.php?p=64228091&postcount=420) for further information about applet inclusion, zip renaming and special features.
