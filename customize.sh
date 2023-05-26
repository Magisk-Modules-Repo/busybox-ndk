# Diffusion Installer Core (DO NOT CHANGE)
# osm0sis @ xda-developers

# keep Magisk's forced module installer backend involvement minimal (must end without ";")
SKIPUNZIP=1

# make sure variables are correct regardless of Magisk or recovery sourcing the script
if [ -z $OUTFD ]; then
  OUTFD=/proc/self/fd/$2;
else
  OUTFD=/proc/self/fd/$OUTFD;
fi;
[ -z $TMPDIR ] && TMPDIR=/dev/tmp;
[ ! -z $ZIP ] && { ZIPFILE="$ZIP"; unset ZIP; }
[ -z $ZIPFILE ] && ZIPFILE="$3";
DIR=$(dirname "$ZIPFILE");

[ "$ANDROID_ROOT" ] || ANDROID_ROOT=/system;

# embedded mode support
if readlink /proc/$$/fd/$2 2>/dev/null | grep -q /tmp; then
  # rerouted to log file, so suppress recovery ui commands
  OUTFD=/proc/self/fd/0;
  # try to find the actual fd (pipe with parent updater likely started as 'update-binary 3 fd zipfile')
  for FD in $(ls /proc/$$/fd); do
    if readlink /proc/$$/fd/$FD 2>/dev/null | grep -q pipe; then
      if ps | grep " 3 $FD " | grep -v grep >/dev/null; then
        OUTFD=/proc/self/fd/$FD;
        break;
      fi;
    fi;
  done;
fi;

# Magisk app/booted flashing support
[ -e /data/adb/magisk ] && ADB=adb;
BOOTMODE=false;
ps | grep zygote | grep -v grep >/dev/null && BOOTMODE=true;
$BOOTMODE || ps -A 2>/dev/null | grep zygote | grep -v grep >/dev/null && BOOTMODE=true;
if $BOOTMODE; then
  OUTFD=/proc/self/fd/0;
  if [ -e /data/$ADB/magisk ]; then
    if [ ! -f /data/$ADB/magisk_merge.img -a ! -e /data/adb/modules ]; then
      (/system/bin/make_ext4fs -b 4096 -l 64M /data/$ADB/magisk_merge.img || /system/bin/mke2fs -b 4096 -t ext4 /data/$ADB/magisk_merge.img 64M) >/dev/null;
    fi;
    [ -e /magisk/.core/busybox ] && MAGISKBB=/magisk/.core/busybox;
    [ -e /sbin/.core/busybox ] && MAGISKBB=/sbin/.core/busybox;
    [ -e /sbin/.magisk/busybox ] && MAGISKBB=/sbin/.magisk/busybox;
    [ -e /dev/*/.magisk/busybox ] && MAGISKBB=$(echo /dev/*/.magisk/busybox);
    [ -e /debug_ramdisk/.magisk/busybox ] && MAGISKBB=/debug_ramdisk/.magisk/busybox;
    [ "$MAGISKBB" ] && export PATH="$MAGISKBB:$PATH";
  fi;
fi;

# postinstall addon.d-v2 awareness
[ -d /postinstall/tmp ] && POSTINSTALL=/postinstall;

ui_print() {
  if $BOOTMODE; then
    echo "$1";
  else
    echo -e "ui_print $1\nui_print" >> $OUTFD;
  fi;
}
show_progress() { echo "progress $1 $2" >> $OUTFD; }
set_progress() { echo "set_progress $1" >> $OUTFD; }
file_getprop() { grep "^$2=" "$1" | tail -n1 | cut -d= -f2-; }
set_perm() {
  local uid gid mod;
  uid=$1; gid=$2; mod=$3;
  shift 3;
  chown $uid:$gid "$@" || chown $uid.$gid "$@";
  chmod $mod "$@";
}
set_perm_recursive() {
  local uid gid dmod fmod;
  uid=$1; gid=$2; dmod=$3; fmod=$4;
  shift 4;
  while [ "$1" ]; do
    chown -R $uid:$gid "$1" || chown -R $uid.$gid "$1";
    find "$1" -type d -exec chmod $dmod {} +;
    find "$1" -type f -exec chmod $fmod {} +;
    shift;
  done;
}
find_slot() {
  local slot=$(getprop ro.boot.slot_suffix 2>/dev/null);
  [ "$slot" ] || slot=$(grep -o 'androidboot.slot_suffix=.*$' /proc/cmdline | cut -d\  -f1 | cut -d= -f2);
  if [ ! "$slot" ]; then
    slot=$(getprop ro.boot.slot 2>/dev/null);
    [ "$slot" ] || slot=$(grep -o 'androidboot.slot=.*$' /proc/cmdline | cut -d\  -f1 | cut -d= -f2);
    [ "$slot" ] && slot=_$slot;
  fi;
  [ "$slot" == "normal" ] && unset slot;
  [ "$slot" ] && echo "$slot";
}
setup_mountpoint() {
  [ -L $1 ] && mv -f $1 ${1}_link;
  if [ ! -d $1 ]; then
    rm -f $1;
    mkdir -p $1;
  fi;
}
is_mounted() { mount | grep -q " $1 "; }
mount_apex() {
  [ -d /system_root/system/apex ] || return 1;
  local apex dest loop minorx num shcon var;
  setup_mountpoint /apex;
  mount -t tmpfs tmpfs /apex -o mode=755 && touch /apex/apextmp;
  shcon=$(cat /proc/self/attr/current);
  echo "u:r:su:s0" > /proc/self/attr/current; # work around LOS Recovery not allowing loop mounts in recovery context
  minorx=1;
  [ -e /dev/block/loop1 ] && minorx=$(ls -l /dev/block/loop1 | awk '{ print $6 }');
  num=0;
  for apex in /system_root/system/apex/*; do
    dest=/apex/$(basename $apex | sed -E -e 's;\.apex$|\.capex$;;' -e 's;\.current$|\.release$;;');
    mkdir -p $dest;
    case $apex in
      *.apex|*.capex)
        unzip -qo $apex original_apex -d /apex;
        [ -f /apex/original_apex ] && apex=/apex/original_apex;
        unzip -qo $apex apex_payload.img -d /apex;
        mv -f /apex/original_apex $dest.apex 2>/dev/null;
        mv -f /apex/apex_payload.img $dest.img;
        mount -t ext4 -o ro,noatime $dest.img $dest 2>/dev/null && echo "$dest (direct)" >&2;
        if [ $? != 0 ]; then
          while [ $num -lt 64 ]; do
            loop=/dev/block/loop$num;
            [ -e $loop ] || mknod $loop b 7 $((num * minorx));
            losetup $loop $dest.img 2>/dev/null;
            num=$((num + 1));
            losetup $loop | grep -q $dest.img && break;
          done;
          mount -t ext4 -o ro,loop,noatime $loop $dest && echo "$dest (loop)" >&2;
          if [ $? != 0 ]; then
            losetup -d $loop 2>/dev/null;
            if [ $num -eq 64 -a $(losetup -f) == "/dev/block/loop0" ]; then
              echo "Aborting apex mounts due to broken environment..." >&2;
              break;
            fi;
          fi;
        fi;
      ;;
      *) mount -o bind $apex $dest && echo "$dest (bind)" >&2;;
    esac;
  done;
  echo "$shcon" > /proc/self/attr/current;
  for var in $(grep -o 'export .* /.*' /system_root/init.environ.rc | awk '{ print $2 }'); do
    eval OLD_${var}=\$$var;
  done;
  $(grep -o 'export .* /.*' /system_root/init.environ.rc | sed 's; /;=/;'); unset export;
  touch /apex/apexdfn;
}
umount_apex() {
  [ -f /apex/apexdfn ] || return 1;
  echo "Unmounting apex..." >&2;
  local dest loop var;
  for var in $(grep -o 'export .* /.*' /system_root/init.environ.rc 2>/dev/null | awk '{ print $2 }'); do
    if [ "$(eval echo \$OLD_$var)" ]; then
      eval $var=\$OLD_${var};
    else
      eval unset $var;
    fi;
    unset OLD_${var};
  done;
  for dest in $(find /apex -type d -mindepth 1 -maxdepth 1); do
    loop=$(mount | grep $dest | grep loop | cut -d\  -f1);
    umount -l $dest;
    losetup $loop >/dev/null 2>&1 && losetup -d $loop;
  done;
  [ -f /apex/apextmp ] && umount /apex;
  rm -rf /apex/apexdfn /apex 2>/dev/null;
}
mount_all() {
  local byname mount slot system;
  echo "Mounting..." >&2;
  byname=bootdevice/by-name;
  [ -d /dev/block/$byname ] || byname=$(find /dev/block/platform -type d -name by-name 2>/dev/null | head -n1 | cut -d/ -f4-);
  [ -e /dev/block/$byname/super -a -d /dev/block/mapper ] && byname=mapper;
  [ -e /dev/block/$byname/system ] || slot=$(find_slot);
  for mount in /cache /data /metadata /persist; do
    if ! is_mounted $mount; then
      mount $mount 2>/dev/null && echo "$mount (fstab)" >&2 && UMOUNTLIST="$UMOUNTLIST $mount";
      if [ $? != 0 -a -e /dev/block/$byname$mount ]; then
        setup_mountpoint $mount;
        mount -o ro -t auto /dev/block/$byname$mount $mount && echo "$mount (direct)" >&2 && UMOUNTLIST="$UMOUNTLIST $mount";
      fi;
    fi;
  done;
  setup_mountpoint $ANDROID_ROOT;
  if ! is_mounted $ANDROID_ROOT; then
    mount -o ro -t auto $ANDROID_ROOT 2>/dev/null && echo "$ANDROID_ROOT (\$ANDROID_ROOT)" >&2;
  fi;
  case $ANDROID_ROOT in
    /system_root) setup_mountpoint /system;;
    /system)
      if ! is_mounted /system && ! is_mounted /system_root; then
        setup_mountpoint /system_root;
        mount -o ro -t auto /system_root && echo "/system_root (fstab)" >&2;
      elif [ -f /system/system/build.prop ]; then
        setup_mountpoint /system_root;
        mount --move /system /system_root && echo "/system_root (moved)" >&2;
      fi;
      if [ $? != 0 ]; then
        (umount /system;
        umount -l /system) 2>/dev/null;
        mount -o ro -t auto /dev/block/$byname/system$slot /system_root && echo "/system_root (direct)" >&2;
      fi;
    ;;
  esac;
  [ -f /system_root/system/build.prop ] && system=/system;
  for mount in /vendor /product /system_ext; do
    mount -o ro -t auto $mount 2>/dev/null && echo "$mount (fstab)" >&2;
    if [ $? != 0 ] && [ -L /system$mount -o -L /system_root$system$mount ]; then
      setup_mountpoint $mount;
      mount -o ro -t auto /dev/block/$byname$mount$slot $mount && echo "$mount (direct)" >&2;
    fi;
  done;
  if is_mounted /system_root; then
    mount_apex;
    mount -o bind /system_root$system /system && echo "/system (bind)" >&2;
  fi;
  echo " " >&2;
}
umount_all() {
  local mount;
  echo "Unmounting..." >&2;
  (if [ ! -d /postinstall/tmp ]; then
    umount /system;
    umount -l /system;
  fi) 2>/dev/null;
  umount_apex;
  (if [ ! -d /postinstall/tmp ]; then
    umount /system_root;
    umount -l /system_root;
  fi;
  for mount in /mnt/system /vendor /mnt/vendor /product /mnt/product /system_ext /mnt/system_ext $UMOUNTLIST; do
    umount $mount;
    umount -l $mount;
  done) 2>/dev/null;
}
setup_env() {
  $BOOTMODE && return 1;
  mount -o bind /dev/urandom /dev/random;
  if [ -L /etc ]; then
    setup_mountpoint /etc;
    cp -af /etc_link/* /etc;
    sed -i 's; / ; /system_root ;' /etc/fstab;
  fi;
  umount_all;
  mount_all;
  OLD_LD_PATH=$LD_LIBRARY_PATH;
  OLD_LD_PRE=$LD_PRELOAD;
  OLD_LD_CFG=$LD_CONFIG_FILE;
  unset LD_LIBRARY_PATH LD_PRELOAD LD_CONFIG_FILE;
  if [ ! "$(getprop 2>/dev/null)" ]; then
    getprop() {
      local propdir propfile propval;
      for propdir in / /system_root /system /vendor /product /product/etc /system_ext/etc /odm/etc; do
        for propfile in default.prop build.prop; do
          if [ "$propval" ]; then
            break 2;
          else
            propval="$(file_getprop $propdir/$propfile $1 2>/dev/null)";
          fi;
        done;
      done;
      echo "$propval";
    }
  elif [ ! "$(getprop ro.build.type 2>/dev/null)" ]; then
    getprop() {
      ($(which getprop) | grep "$1" | cut -d[ -f3 | cut -d] -f1) 2>/dev/null;
    }
  fi;
}
restore_env() {
  $BOOTMODE && return 1;
  local dir;
  unset -f getprop;
  [ "$OLD_LD_PATH" ] && export LD_LIBRARY_PATH=$OLD_LD_PATH;
  [ "$OLD_LD_PRE" ] && export LD_PRELOAD=$OLD_LD_PRE;
  [ "$OLD_LD_CFG" ] && export LD_CONFIG_FILE=$OLD_LD_CFG;
  unset OLD_LD_PATH OLD_LD_PRE OLD_LD_CFG;
  sleep 1;
  umount_all;
  [ -L /etc_link ] && rm -rf /etc/*;
  (for dir in /etc /apex /system_root /system /vendor /product /system_ext /metadata /persist; do
    if [ -L "${dir}_link" ]; then
      rmdir $dir;
      mv -f ${dir}_link $dir;
    fi;
  done;
  umount -l /dev/random) 2>/dev/null;
}
find_zip_opts() {
  # if options are disabled then zip is install-only
  ACTION=installation;
  $USE_ZIP_OPTS || return 1;
  local choice; 
  # zip filename or settings file install options parsing
  if [ -f /data/.$MODID ]; then
    choice=$(cat /data/.$MODID);
  else
    choice=$(basename "$ZIPFILE");
  fi;
  case $choice in
    *uninstall*|*Uninstall*|*UNINSTALL*) ACTION=uninstallation;;
  esac;
  case $choice in
    *system*|*System*|*SYSTEM*) FORCE_SYSTEM=1; ui_print " "; ui_print "Warning: Forcing a system $ACTION!";;
  esac;
  custom_zip_opts;
}
find_arch() {
  $USE_ARCH || return 1;
  local abi=$(file_getprop /system/build.prop ro.product.cpu.abi);
  case $abi in
    arm*|x86*|mips*) ;;
    *) abi=$(getprop ro.product.cpu.abi);;
  esac;
  case $abi in
    arm*|x86*|mips*) ;;
    *) abi=$(file_getprop /default.prop ro.product.cpu.abi);;
  esac;
  case $abi in
    arm64*) ARCH=arm64;;
    arm*) ARCH=arm;;
    x86_64*) ARCH=x86_64;;
    x86*) ARCH=x86;;
    mips64*) ARCH=mips64;;
    mips*) ARCH=mips;;
    *) ui_print "Unknown architecture: $abi"; abort;;
  esac;
}
mount_su() {
  [ ! -e $MNT ] && mkdir -p $MNT;
  mount -t ext4 -o rw,noatime $SUIMG $MNT;
  if [ $? != 0 ]; then
    minorx=1;
    [ -e /dev/block/loop1 ] && minorx=$(ls -l /dev/block/loop1 | cut -d, -f2 | cut -c4);
    i=0;
    while [ $i -lt 64 ]; do
      LOOP=/dev/block/loop$i;
      (mknod $LOOP b 7 $((i * minorx));
      losetup $LOOP $SUIMG) 2>/dev/null;
      i=$((i + 1));
      losetup $LOOP | grep -q $SUIMG && break;
    done;
    mount -t ext4 -o loop,noatime $LOOP $MNT;
    if [ $? != 0 ]; then
      losetup -d $LOOP 2>/dev/null;
    fi;
  fi;
}
find_target() {
  local block i minorx slot;
  # magisk.img clean flash support
  if [ -e /data/$ADB/magisk -a ! -e /data/$ADB/magisk.img -a ! -e /data/adb/modules ]; then
    make_ext4fs -b 4096 -l 64M /data/$ADB/magisk.img || mke2fs -b 4096 -t ext4 /data/$ADB/magisk.img 64M;
  fi;
  # allow forcing a system installation regardless of su.img/magisk.img detection
  if [ ! "$FORCE_SYSTEM" ]; then
    SUIMG=`(ls /data/$ADB/magisk_merge.img || ls /data/su.img || ls /cache/su.img || ls /data/$ADB/magisk.img || ls /cache/magisk.img) 2>/dev/null`;
  fi;
  # SuperSU su.img and Magisk magisk.img/magisk_merge.img module support
  if [ "$SUIMG" ]; then
    MNT=$TMPDIR/$(basename $SUIMG .img);
    umount $MNT;
    mount_su;
    case $MNT in
      */magisk*) MAGISK=/$MODID/system;;
    esac;
  else
    if [ ! "$FORCE_SYSTEM" ]; then
      # SuperSU BINDSBIN support
      MNT=$(dirname `find /data -name supersu_is_here | head -n1` 2>/dev/null);
      if [ -e "$MNT" ]; then
        BINDSBIN=1;
      # Magisk /data/adb module support
      elif [ -e /data/adb/modules ]; then
        MNT=/data/adb/modules_update;
        MAGISK=/$MODID/system;
      fi;
    fi;
    # system support
    if [ ! "$MNT" ]; then
      MNT=$POSTINSTALL/system;
      if [ ! -d /postinstall/tmp ]; then
        if [ -d /dev/block/mapper ]; then
          for block in system vendor product system_ext; do
            for slot in "" _a _b; do
              blockdev --setrw /dev/block/mapper/$block$slot 2>/dev/null;
            done;
          done;
        fi;
        mount -o rw,remount -t auto /system || mount /system;
        [ $? != 0 ] && mount -o rw,remount -t auto / && SAR=1;
        (mount -o rw,remount -t auto /vendor;
        mount -o rw,remount -t auto /product;
        mount -o rw,remount -t auto /system_ext) 2>/dev/null;
      fi;
    fi;
  fi;
  # set target paths
  TARGET=$MNT$MAGISK;
  custom_target; # allow modifying $TARGET before $ETC, $BIN and $XBIN get set
  ETC=$TARGET/etc;
  BIN=$TARGET/bin;
  if [ -d "$TARGET/xbin" -o "$MAGISK" -a -d /system/xbin ]; then
    XBIN=$TARGET/xbin;
  else
    XBIN=$BIN;
  fi;
}
do_install() {
  local dir mount targetvar;
  mkdir -p $TARGET;
  # handle $BIN $XBIN and $ETC
  for dir in bin xbin etc; do
    if [ -d $dir ]; then
      cd $dir;
      targetvar=$(echo $dir | tr '[:lower:]' '[:upper:]');
      eval mkdir -p \$$targetvar;
      eval cp -rfpL * \$$targetvar;
      cd ..;
    fi;
  done;
  # handle system $TARGET
  for mount in vendor product system_ext; do
    if [ "$MAGISK" -a -d $mount ]; then
      mkdir system 2>/dev/null;
      mv -f $mount system;
    fi;
  done;
  [ -d system ] && cp -rfpL system/* $TARGET;
  # handle paths that aren't/can't be part of a systemless solution
  for dir in cache data metadata persist vendor product system_ext; do
    if [ -d $dir ]; then
      cd $dir;
      cp -rfpL * /$dir;
      cd ..;
    fi;
  done;
}
update_magisk() {
  [ "$MAGISK" ] || return 1;
  cp -fp module.prop $MNT/$MODID/;
  touch $MNT/$MODID/auto_mount;
  if $BOOTMODE; then
    IMGMNT=/sbin/.core/img;
    [ -e /magisk ] && IMGMNT=/magisk;
    [ -e /sbin/.magisk/img ] && IMGMNT=/sbin/.magisk/img;
    [ -e /data/adb/modules ] && IMGMNT=/data/adb/modules;
    mkdir -p "$IMGMNT/$MODID";
    touch "$IMGMNT/$MODID/update";
    cp -fp module.prop "$IMGMNT/$MODID/";
  fi;
}
do_uninstall() {
  local dir rmdir rmfile targetvar;
  # handle $BIN $XBIN and $ETC
  for dir in bin xbin etc; do
    if [ -d $dir ]; then
      cd $dir;
      targetvar=$(echo $dir | tr '[:lower:]' '[:upper:]');
      for rmfile in $(find . -type f); do
        eval rm -f \$$targetvar/$rmfile;
      done;
      for rmdir in $(find . -type d); do
        eval rmdir -p \$$targetvar/$rmdir;
      done;
      cd ..;
    fi;
  done;
  for mount in vendor product system_ext; do
    if [ "$MAGISK" -a -d $mount ]; then
      mkdir system 2>/dev/null;
      mv -f $mount system;
    fi;
  done;
  # handle system $TARGET
  if [ -d system ]; then
    cd system;
    for rmfile in $(find . -type f); do
      rm -f $TARGET/$rmfile;
    done;
    for rmdir in $(find . -type d); do
      rmdir -p $TARGET/$rmdir;
    done;
    cd ..;
  fi;
  # handle paths that aren't/can't be part of a systemless solution
  for dir in cache data metadata persist vendor product system_ext; do
    if [ -d $dir ]; then
      cd $dir;
      for rmfile in $(find . -type f); do
        rm -f /$dir/$rmfile;
      done;
      for rmdir in $(find . -type d); do
        rmdir -p /$dir/$rmdir;
      done;
      cd ..;
    fi;
  done;
  rmdir -p $TARGET;
}
abort() {
  ui_print " ";
  ui_print "Your system has not been changed.";
  ui_print " ";
  ui_print "Script will now exit...";
  ui_print " ";
  [ "$SUIMG" ] && umount $MNT;
  [ "$LOOP" ] && losetup -d $LOOP;
  [ "$SAR" ] && mount -o ro,remount -t auto /;
  restore_env;
  umask $UMASK;
  exit 1;
}

UMASK=$(umask);
umask 022;

# ensure zip installer shell is in a working scratch directory
mkdir -p $TMPDIR;
cd $TMPDIR;

# source custom installer functions and configuration
unzip -o "$ZIPFILE" diffusion_config.sh module.prop;
MODID=$(file_getprop module.prop id);
. ./diffusion_config.sh;

# only print custom title if not sourced by Magisk's forced backend
if [ -z $MODPATH ]; then
  ui_print " ";
  ui_print "$INST_NAME";
  ui_print "by $AUTH_NAME";
fi;
show_progress 1.34 0;

ui_print " ";
ui_print "Mounting...";
setup_env;

custom_setup;
find_zip_opts;
set_progress 0.2;

ui_print " ";
ui_print "Extracting files...";
mkdir -p $TMPDIR/$MODID;
cd $TMPDIR/$MODID;
unzip -o "$ZIPFILE";
set_perm_recursive 0 0 755 644 .;
set_progress 0.3;

if [ "$ACTION" == installation ]; then
  ui_print " ";
  ui_print "Installing...";
  find_arch;
  find_target; # and custom_target

  do_install;
  custom_install;

  update_magisk;
  set_progress 0.8;

  custom_cleanup;
  custom_postinstall;

  if [ "$MAGISK" ]; then
    rm -f $MNT/$MODID/customize.sh;
    chcon -hR 'u:object_r:system_file:s0' "$MNT/$MODID";
  fi;
else
  ui_print " ";
  ui_print "Uninstalling...";
  find_target; # and custom_target

  do_uninstall;
  custom_uninstall;

  custom_cleanup;
  custom_postuninstall;

  if [ "$MAGISK" ]; then
    rm -rf /magisk/$MODID /sbin/.core/img/$MODID /sbin/.magisk/img/$MODID /data/adb/modules/$MODID /data/adb/modules_update/$MODID;
    rmdir /data/adb/modules_update 2>/dev/null;
  fi;
fi;
set_progress 1.0;

ui_print " ";
ui_print "Unmounting...";
cd /;
[ "$SUIMG" ] && umount $MNT;
[ "$LOOP" ] && losetup -d $LOOP;
[ "$SAR" ] && mount -o ro,remount -t auto /;
restore_env;
set_progress 1.2;

rm -rf $TMPDIR;
umask $UMASK;
ui_print " ";
ui_print "Done!";
set_progress 1.34;
custom_exitmsg;
exit 0;

