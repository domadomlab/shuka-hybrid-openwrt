#!/bin/bash
PKG_NAME="luci-app-shuka-hybrid"
VERSION="3.0.0-LTS"
ARCH="aarch64"
BUILD_DIR="/tmp/shuka_lts_build"
TARGET_IPK="${PKG_NAME}_${VERSION}_${ARCH}.ipk"

echo "Building LTS IPK: $TARGET_IPK"

rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR/data/usr/bin
mkdir -p $BUILD_DIR/data/usr/lib/lua/luci/controller
mkdir -p $BUILD_DIR/data/etc/init.d
mkdir -p $BUILD_DIR/data/etc/sing-box
mkdir -p $BUILD_DIR/data/etc/hotplug.d/iface
mkdir -p $BUILD_DIR/control

cp bin/* $BUILD_DIR/data/usr/bin/
cp scripts/* $BUILD_DIR/data/usr/bin/
cp init/shuka-boot.init $BUILD_DIR/data/etc/init.d/shuka-boot
cp init/internet-protection.init $BUILD_DIR/data/etc/init.d/internet-protection
cp hotplug/98-shuka-modem-vpn $BUILD_DIR/data/etc/hotplug.d/iface/
cp luci/shuka_hybrid.lua $BUILD_DIR/data/usr/lib/lua/luci/controller/
cp config.json.template $BUILD_DIR/data/etc/sing-box/
[ -f amnezia_template.conf ] && cp amnezia_template.conf $BUILD_DIR/data/etc/sing-box/

chmod +x $BUILD_DIR/data/usr/bin/*
chmod +x $BUILD_DIR/data/etc/init.d/*
chmod +x $BUILD_DIR/data/etc/hotplug.d/iface/*

cat <<CTRL_EOF > $BUILD_DIR/control/control
Package: $PKG_NAME
Version: $VERSION
Depends: libc, kmod-tun, iptables, ip-full, python3-light, python3-urllib, python3-openssl, python3-codecs, ca-bundle, curl, ca-certificates
Architecture: $ARCH
Maintainer: domadomlab
Description: Shuka Hybrid Suite LTS (Stable Router Version).
CTRL_EOF

cat <<POST_EOF > $BUILD_DIR/control/postinst
#!/bin/sh
/etc/init.d/internet-protection enable
/etc/init.d/shuka-boot enable
[ -L /lib/ld-linux-aarch64.so.1 ] || ln -s /lib/libc.so /lib/ld-linux-aarch64.so.1
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache
/etc/init.d/uhttpd restart
exit 0
POST_EOF
chmod +x $BUILD_DIR/control/postinst

cat <<PRERM_EOF > $BUILD_DIR/control/prerm
#!/bin/sh
/etc/init.d/internet-protection disable
/etc/init.d/shuka-boot disable
exit 0
PRERM_EOF
chmod +x $BUILD_DIR/control/prerm

echo "2.0" > $BUILD_DIR/debian-binary

cd $BUILD_DIR/control
tar --owner=0 --group=0 -czf ../control.tar.gz ./*
cd $BUILD_DIR/data
tar --owner=0 --group=0 -czf ../data.tar.gz ./*
cd $BUILD_DIR
tar --owner=0 --group=0 -czf /home/dom/.gemini/shuka-github-repo/$TARGET_IPK debian-binary data.tar.gz control.tar.gz

echo "Done! IPK is in /home/dom/.gemini/shuka-github-repo/$TARGET_IPK"
