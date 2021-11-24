# Diffusion Installer Config
# osm0sis @ xda-developers

INST_NAME="Busybox Installer Script";
AUTH_NAME="osm0sis @ xda-developers";

USE_ARCH=true
USE_ZIP_OPTS=true

custom_setup() {
  return # stub
}

custom_zip_opts() {
  case $choice in
    *nolinks*|*NoLinks*|*NOLINKS*) NOLINKS=1;
  esac;
  case $choice in
    *noselinux*|*NoSELinux*|*NOSELINUX*) ;;
    *) SELINUX=-selinux;;
  esac;
}

custom_target() {
  return # stub
}

custom_install() {
  case $ARCH in
    mips*) unset SELINUX;;
  esac;
  ui_print "Using architecture: $ARCH$SELINUX";
  ui_print "Using path: $XBIN";
  mkdir -p $XBIN;
  cp -f busybox-$ARCH$SELINUX $XBIN/busybox;
  set_perm 0 0 755 $XBIN/busybox;
}

custom_postinstall() {
  local applet existbin sysbin;
  if [ ! "$NOLINKS" ]; then
    ui_print " ";
    ui_print "Creating symlinks...";
    sysbin="$(ls /system/bin)";
    $BOOTMODE && existbin="$(ls $IMGMNT/$MODID/system/bin 2>/dev/null)";
    for applet in $($XBIN/busybox --list); do
      case $XBIN in
        */bin)
          if [ "$(echo "$sysbin" | $XBIN/busybox grep -xF "$applet")" ]; then
            if $BOOTMODE && [ "$(echo "$existbin" | $XBIN/busybox grep -xF "$applet")" ]; then
              $XBIN/busybox ln -sf busybox $applet;
            fi;
          else
            $XBIN/busybox ln -sf busybox $applet;
          fi;
        ;;
        *) $XBIN/busybox ln -sf busybox $applet;;
      esac;
    done;
  fi;
}

custom_uninstall() {
  if [ ! -f "$XBIN/busybox" -a ! "$MAGISK" ]; then
    ui_print " ";
    ui_print "No busybox installation found!";
    abort;
  fi;
  LIST=busybox;
}

custom_postuninstall() {
  return # stub
}

custom_cleanup() {
  local cleanup dir i;
  ui_print " ";
  ui_print "Cleaning...";
  cleanup=$XBIN;
  if [ "$XBIN" == "$MNT$MAGISK/xbin" -a -f "$MNT$MAGISK/bin/busybox" ]; then
    $XBIN/busybox rm -f $MNT$MAGISK/bin/busybox;
    cleanup="$MNT$MAGISK/bin $XBIN";
  fi;
  for dir in $cleanup; do
    cd $dir;
    for i in $(ls -al `find -type l` | $XBIN/busybox awk '{ print $(NF-2) ":" $NF }'); do
      case $(echo $i | $XBIN/busybox cut -d: -f2) in
        *busybox) LIST="$LIST $dir/$(echo $i | $XBIN/busybox cut -d: -f1)";;
      esac;
    done;
  done;
  $XBIN/busybox rm -f $LIST;
}

custom_exitmsg() {
  return # stub
}

# additional custom functions


