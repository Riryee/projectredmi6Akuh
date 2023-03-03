
SKIPUNZIP=1
ASH_STANDALONE=1

status=""
architecture=""
latest=$(date +%Y%m%d%H%M)

if $BOOTMODE; then
  ui_print "- Installing from Magisk app"
else
  ui_print "*********************************************************"
  ui_print "! Install from recovery is NOT supported"
  ui_print "! Some recovery has broken implementations, install with such recovery will finally cause BFM modules not working"
  ui_print "! Please install from Magisk app"
  abort "*********************************************************"
fi

# check Magisk
ui_print "- Magisk version: $MAGISK_VER ($MAGISK_VER_CODE)"

# check android
if [ "$API" -lt 28 ]; then
  ui_print "! Unsupported sdk: $API"
  abort "! Minimal supported sdk is 28 (Android 9)"
else
  ui_print "- Device sdk: $API"
fi

ui_print "- check architecture"
case $ARCH in
  arm|arm64|x86|x64)
    ui_print "- Device platform: $ARCH"
    ;;
  *)
    abort "! Unsupported platform: $ARCH"
    ;;
esac

ui_print "- Installing Box for Magisk"

if [ -d "/data/adb/box" ] ; then
    ui_print "- Backup box"
    mkdir -p "/data/adb/box/${latest}"
    mv /data/adb/box/* "/data/adb/box/${latest}/"
fi

ui_print "- Set architecture ${ARCH}"
case "${ARCH}" in
  arm)
    architecture="armv7"
    ;;
  arm64)
    architecture="armv8"
    ;;
  x86)
    architecture="386"
    ;;
  x64)
    architecture="amd64"
    ;;
  *)
    abort "Error: Unsupported architecture ${ARCH}"
    ;;
esac

ui_print "- Create directories"
mkdir -p "${MODPATH}/system/bin"
mkdir -p "${MODPATH}/system/etc/security/cacerts"
mkdir -p "/data/adb/box"
mkdir -p "/data/adb/box/bin"
mkdir -p "/data/adb/box/run"
mkdir -p "/data/adb/box/scripts"
mkdir -p "/data/adb/box/xray"
mkdir -p "/data/adb/box/v2fly"
mkdir -p "/data/adb/box/sing-box"
mkdir -p "/data/adb/box/clash"
mkdir -p "/data/adb/box/dashboard"
mkdir -p "/data/adb/box/clash/dashboard"
mkdir -p "/data/adb/box/sing-box/dashboard"

ui_print "- Ekstrak file ZIP dan skip folder META-INF ke dalam folder MODPATH"
unzip -o "${ZIPFILE}" -x 'META-INF/*' -d "${MODPATH}" >&2

ui_print "- Ekstrak file uninstall.sh dan box_service.sh ke dalam folder MODPATH dan /data/adb/service.d"
unzip -j -o "${ZIPFILE}" 'uninstall.sh' -d "${MODPATH}" >&2
unzip -j -o "${ZIPFILE}" 'box_service.sh' -d /data/adb/service.d >&2

ui_print "- Ekstrak file dari arsip binary dan salin ke folder /system/bin dan /data/adb/box/bin"
tar -xjf "${MODPATH}/binary/${ARCH}.tar.bz2" -C "${MODPATH}/system/bin" >&2
tar -xjf "${MODPATH}/binary/${ARCH}.tar.bz2" "mlbox" -C /data/adb/box/bin >&2

# tar -xjf ${MODPATH}/binary/${ARCH}.tar.bz2 "xray" -C /data/adb/box/bin >&2
# tar -xjf ${MODPATH}/binary/${ARCH}.tar.bz2 "clash" -C /data/adb/box/bin >&2
# tar -xjf ${MODPATH}/binary/${ARCH}.tar.bz2 "v2fly" -C /data/adb/box/bin >&2
# tar -xjf ${MODPATH}/binary/${ARCH}.tar.bz2 "sing-box" -C /data/adb/box/bin >&2

ui_print "- Ekstrak file dashboard.zip ke dalam folder /data/adb/box/clash/dashboard dan /data/adb/box/sing-box/dashboard"
unzip -o "${MODPATH}/dashboard.zip" -d /data/adb/box/dashboard/ >&2
unzip -o "${MODPATH}/dashboard.zip" -d /data/adb/box/clash/dashboard/ >&2
unzip -o "${MODPATH}/dashboard.zip" -d /data/adb/box/sing-box/dashboard >&2

# ui_print "- Buat file resolv.conf jika belum ada dan tambahkan server nameserver"
# if [ ! -f "/data/adb/modules/box_for_magisk/system/etc/resolv.conf" ]; then
  # cat > "${MODPATH}/system/etc/resolv.conf" <<EOF
# nameserver 8.8.8.8
# nameserver 1.1.1.1
# nameserver 9.9.9.9
# nameserver 94.140.14.14
# EOF
# fi

ui_print "- Move BFM files"
mv "$MODPATH/scripts/cacert.pem" "$MODPATH/system/etc/security/cacerts"
mv "$MODPATH/scripts/src/"* "/data/adb/box/scripts/"
mv "$MODPATH/scripts/clash/"* "/data/adb/box/clash/"
mv "$MODPATH/scripts/settings.ini" "/data/adb/box/"
mv "$MODPATH/scripts/xray" "/data/adb/box/"
mv "$MODPATH/scripts/v2fly" "/data/adb/box/"
mv "$MODPATH/scripts/sing-box" "/data/adb/box/"

ui_print "- Delete leftover files"
rm -rf "${MODPATH}/scripts"
rm -rf "${MODPATH}/binary"
rm -f "${MODPATH}/box_service.sh"
rm -f "${MODPATH}/dashboard.zip"
sleep 1

ui_print "- Setting permissions"
set_perm_recursive "${MODPATH}" 0 0 0755 0644
set_perm_recursive "/data/adb/box/" 0 3005 0755 0644
set_perm_recursive "/data/adb/box/scripts/" 0 3005 0755 0700
set_perm "/data/adb/service.d/box_service.sh"  0  0  0755
set_perm "${MODPATH}/service.sh"  0  0  0755
set_perm "${MODPATH}/uninstall.sh"  0  0  0755
set_perm "${MODPATH}/system/etc/security/cacerts/cacert.pem" 0 0 0644=
chmod ugo+x /data/adb/box/*
chmod ugo+x /data/adb/box/bin/*
chmod ugo+x /data/adb/box/scripts/*
chmod ugo+x ${MODPATH}/system/bin/*
ui_print "- Installation is complete, reboot your device"
ui_print " --- Notes --- "
ui_print "[+] report issues to @taamarin on Telegram"
ui_print "[+] Join @taamarin on telegram to get more updates"