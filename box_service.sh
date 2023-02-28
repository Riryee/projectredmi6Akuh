#!/system/bin/sh

(
    until [ $(getprop init.svc.bootanim) = "stopped" ]; do
        sleep 3
    done

    if [ -f "/data/adb/box/scripts/start.sh" ]; then
        chmod 755 /data/adb/box/scripts/start.sh
        /data/adb/box/scripts/start.sh
    else
        echo "File '/data/adb/box/scripts/start.sh' not found"
    fi
)&