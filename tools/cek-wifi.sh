#!/bin/bash
# Kumpulkan bukti untuk Wi-Fi yang mentok di "obtaining IP address".
# Dijalankan di mesin yang tercolok perangkat.
#
#   bash cek-wifi.sh
#
# Windows PowerShell: jalankan baris-baris adb di bawah satu per satu, atau
# pakai Git Bash / WSL.
#
# URUTANNYA PENTING: logcat dibersihkan DULU, baru Wi-Fi disambungkan, supaya
# log hanya berisi percobaan yang gagal dan tidak tenggelam oleh riwayat boot.

set -u
O=${1:-wifi-bukti}
mkdir -p "$O"

adb wait-for-device

echo "== 1. bersihkan logcat, lalu SAMBUNGKAN Wi-Fi di perangkat =="
adb logcat -c 2>/dev/null
adb logcat -b all -c 2>/dev/null
echo "   Sekarang di perangkat: sambungkan ke Wi-Fi, tunggu sampai mentok"
echo "   di 'obtaining IP address' (sekitar 30 detik), lalu tekan ENTER."
read -r _

echo "== 2. kumpulkan =="
# Seluruh buffer, bukan hanya main -- DhcpClient banyak menulis ke system/radio.
adb logcat -b all -d                    > "$O/logcat-all.txt" 2>&1
adb logcat -d | grep -v 'avc: *denied'  > "$O/logcat-bersih.txt" 2>&1

# Mesin keadaan DHCP dan supplicant -- ini yang paling menentukan.
adb logcat -b all -d | grep -iE 'DhcpClient|DhcpPacket|IpClient|wpa_supplicant|WifiNative|WifiStateMachine|ClientModeImpl|dhcp' \
                                        > "$O/dhcp-supplicant.txt" 2>&1

# Apakah antarmuka benar-benar naik dan punya rute?
adb shell ip addr                       > "$O/ip-addr.txt" 2>&1
adb shell ip route                      > "$O/ip-route.txt" 2>&1
adb shell ip -s link                    > "$O/ip-link.txt" 2>&1

# Apakah paket keluar sama sekali? RX/TX pada antarmuka wlan.
adb shell cat /proc/net/dev             > "$O/proc-net-dev.txt" 2>&1

adb shell dumpsys wifi                  > "$O/dumpsys-wifi.txt" 2>&1
adb shell dumpsys connectivity          > "$O/dumpsys-connectivity.txt" 2>&1
adb shell dumpsys network_stack          > "$O/dumpsys-network_stack.txt" 2>&1

adb shell getprop                       > "$O/getprop.txt" 2>&1
adb shell dmesg                         > "$O/dmesg.txt" 2>&1

# Servis yang restarting akan langsung terlihat di sini.
adb shell 'getprop | grep "init\.svc\." | grep -v ": \[running\]" | grep -v ": \[stopped\]"' \
                                        > "$O/svc-tidak-normal.txt" 2>&1

echo "== selesai: $O =="
ls -l "$O" | awk 'NR>1{printf "  %-28s %s B\n", $9, $5}'
