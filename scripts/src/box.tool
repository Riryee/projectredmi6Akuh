#!/system/bin/sh

scripts=$(realpath $0)
scripts_dir=$(dirname ${scripts})
source /data/adb/box/settings.ini

user_agent="${bin_name}"

# membuat log pada terminal
logs() {
  export TZ=Asia/Jakarta
  now=$(date +"%I.%M %p %Z")
  if [ -t 1 ]; then
    case $1 in
      info) echo -n "\033[1;34m${now} [info]: $2\033[0m";;
      port) echo -n "\033[1;33m$2 \033[0m";;
      testing) echo -n "\033[1;34m$2\033[0m";;
      success) echo -n "\033[1;32m$2 \033[0m";;
      failed) echo -n "\033[1;31m$2 \033[0m";;
      *) echo -n "\033[1;35m${now} [$1]: $2\033[0m";;
    esac
  else
    case $1 in
      info) echo -n "${now} [info]: $2" | tee -a ${logs_file} >> /dev/null 2>&1;;
      port) echo -n "$2 " | tee -a ${logs_file} >> /dev/null 2>&1;;
      testing) echo -n "$2" | tee -a ${logs_file} >> /dev/null 2>&1;;
      success) echo -n "$2 " | tee -a ${logs_file} >> /dev/null 2>&1;;
      failed) echo -n "$2 " | tee -a ${logs_file} >> /dev/null 2>&1;;
      *) echo -n "${now} [$1]: $2" | tee -a ${logs_file} >> /dev/null 2>&1;;
    esac
  fi
}

# Memeriksa koneksi internet dengan mlbox
testing() {
  logs info "dns="
  for network in $(${data_dir}/bin/mlbox -timeout=5 -dns="-qtype=A -domain=asia.pool.ntp.org" | grep -v 'timeout' | grep -E '[1-9][0-9]{0,2}(\.[0-9]{1,3}){3}'); do
    ntpip=${network}
    break
  done

  if [ -n "${ntpip}" ]; then
    logs success "done"

    logs testing "http="
    httpIP=$(${data_dir}/bin/mlbox -timeout=5 -http="http://182.254.116.116/d?dn=reddit.com&clientip=1" 2>&1 | grep -Ev 'timeout|httpGetResponse' | grep -E '[1-9][0-9]{0,2}(\.[0-9]{1,3}){3}')
    if [ -n "${httpIP}" ]; then
      httpIP="${httpIP#*\|}"
      logs success "done"
    else
      logs failed "failed"
    fi

    logs testing "https="
    httpsResp=$(${data_dir}/bin/mlbox -timeout=5 -http="https://api.infoip.io" 2>&1 | grep -Ev 'timeout|httpGetResponse' | grep -E '[1-9][0-9]{0,2}(\.[0-9]{1,3}){3}')
    [ -n "${httpsResp}" ] && logs success "done" || logs failed "failed"

    logs testing "udp="
    currentTime=$(${data_dir}/bin/mlbox -timeout=7 -ntp="${ntpip}" | grep -v 'timeout')
    echo "${currentTime}" | grep -qi 'LI:' && \
      logs success "done" || logs failed "failed"
  else
    logs failed "failed"
  fi

  [ -t 1 ] && echo -e "\033[1;31m\033[0m" || echo "" | tee -a ${logs_file} >> /dev/null 2>&1
}

# Memeriksa koneksi internet dengan mlbox
network_check() {
  if [ -f "${data_dir}/bin/mlbox" ]; then
    logs info "Checking internet connection... "
    httpsResp=$(${data_dir}/bin/mlbox -timeout=5 -http="https://api.infoip.io" 2>&1 | grep -Ev 'timeout|httpGetResponse' | grep -E '[1-9][0-9]{0,2}(\.[0-9]{1,3}){3}')
    if [ -n "${httpsResp}" ]; then
      logs success "done"
    else
      logs failed "failed"
      flags=false
    fi
  fi
  if [ -t 1 ]; then
    echo "\033[1;31m""\033[0m"
  else
    echo "" | tee -a ${logs_file} >> /dev/null 2>&1
  fi
  [ "${flags}" != "false" ] || exit 1
}

# Memeriksa apakah suatu binary berjalan dengan mengecek file pid dan cmdline
probe_bin_alive() {
  if [ -f "${pid_file}" ]; then
    cmd_file="/proc/$(pidof "${bin_name}")/cmdline"
    if [ -f "${cmd_file}" ] && grep -q "${bin_name}" "${cmd_file}"; then
      return 0 # binary is alive
    else
      return 1 # binary is not alive
    fi
  else
    return 1 # pid file not found, binary is not alive
  fi
}

# Restart binary, setelah dihentikan dan dijalankan kembali
restart_box() {
  ${scripts_dir}/box.service stop
  sleep 0.5
  ${scripts_dir}/box.service start

  if probe_bin_alive ; then
    ${scripts_dir}/box.iptables renew
    log debug "$(date) ${bin_name} restarted successfully."
  else
    log error "Failed to restart ${bin_name}."
  fi
}

# Set DNS secara manual, mengubah net.ipv4.ip_forward dan net.ipv6.conf.all.forwarding menjadi 1
keep_dns() {
  local_dns1=$(getprop net.dns1)
  local_dns2=$(getprop net.dns2)
  if [ "${local_dns1}" != "${static_dns1}" ] || [ "${local_dns2}" != "${static_dns2}" ] ; then
    setprop net.dns1 "${static_dns1}"
    setprop net.dns2 "${static_dns2}"
  fi
  if [ "$(sysctl net.ipv4.ip_forward)" != "1" ] ; then
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
  fi
  if [ "$(sysctl net.ipv6.conf.all.forwarding)" != "1" ] ; then
    sysctl -w net.ipv6.conf.all.forwarding=1 > /dev/null
  fi
  unset local_dns1
  unset local_dns2
}

# Memperbarui file dari URL
update_file() {
  local file="$1"
  local update_url="$2"
  local file_bak="${file}.bak"
  
  if [ -f "${file}" ]; then
    mv "${file}" "${file_bak}" || return 1
  fi
  
  local request="wget"
  local request+=" --no-check-certificate"
  local request+=" --user-agent ${user_agent}"
  local request+=" -O ${file}"
  local request+=" ${update_url}"

  echo ${request}
  ${request} >&2 || {
    if [ -f "${file_bak}" ]; then
      mv "${file_bak}" "${file}" || true
    fi
    return 1
  }
  
  return 0
}

# Memeriksa dan memperbarui geoip dan geosite
update_subgeo() {
  log info "daily updates"
  network_check
  case "${bin_name}" in
    clash)
      if [ "${meta}" = "false" ] ; then
        geoip_file="${data_dir}/clash/Country.mmdb"
        geoip_url="https://github.com/Loyalsoldier/geoip/raw/release/Country-only-cn-private.mmdb"
      else
        geoip_file="${data_dir}/clash/GeoIP.dat"
        geoip_url="https://github.com/v2fly/geoip/raw/release/geoip-only-cn-private.dat"
      fi
      geosite_file="${data_dir}/clash/GeoSite.dat"
      geosite_url="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
    ;;
    sing-box)
      geoip_file="${data_dir}/sing-box/geoip.db"
      geoip_url="https://github.com/SagerNet/sing-geoip/releases/download/20221012/geoip-cn.db"
      geosite_file="${data_dir}/sing-box/geosite.db"
      geosite_url="https://github.com/CHIZI-0618/v2ray-rules-dat/raw/release/geosite.db"
    ;;
    *)
      geoip_file="${data_dir}/${bin_name}/geoip.dat"
      geoip_url="https://github.com/v2fly/geoip/raw/release/geoip-only-cn-private.dat"
      geosite_file="${data_dir}/${bin_name}/geosite.dat"
      geosite_url="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
    ;;
  esac

  if [ "${auto_update_geox}" = "true" ] && log debug "Downloading ${geoip_url}" && update_file "${geoip_file}" "${geoip_url}" && log debug "Downloading ${geosite_url}" && update_file "${geosite_file}" "${geosite_url}"; then
    log debug "Update geo $(date +"%Y-%m-%d %I.%M %p")"
    flag=false
  fi
  
  if [ "${bin_name}" = "clash" ] && [ "${auto_update_subscription}" = "true" ] && update_file "${clash_config}" "${subscription_url}"; then
    flag=true
    log debug "Downloading ${clash_config}"
  fi
  
  if [ -f "${pid_file}" ] && [ "${flag}" = "true" ]; then
    restart_box
  fi
}

# Memeriksa port detected Bin
port_detection() {
  match_count=0
  if (ss -h > /dev/null 2>&1) ; then
    port=$(ss -antup | grep "${bin_name}" | awk '$7~/'pid=$(pidof ${bin_name})*'/{print $5}' | awk -F ':' '{print $2}' | sort -u)
  else
    log warn "skip port detected"
    exit 0
  fi
  logs debug "${bin_name} port detected: "
  for sub_port in ${port[*]} ; do
    sleep 0.5
    logs port "${sub_port}"
  done

	[ -t 1 ] && echo "\033[1;31m""\033[0m" || echo "" | tee -a ${logs_file} >> /dev/null 2>&1
}

# kill bin
kill_alive() {
  for list in "${bin_list[@]}" ; do
    if pgrep "$list" >/dev/null ; then
      kill -9 $(pgrep "$list") >/dev/null 2>&1 || killall -9 "$list" >/dev/null 2>&1
    fi
  done
}

update_kernel() {
  # su -c /data/adb/box/scripts/box.tool upcore
  meta=true
  # for download clash premium / dev
  dev=true
  network_check
  if [ $(uname -m) = "aarch64" ] ; then
    arch="arm64"
    platform="android"
  else
    arch="armv7"
    platform="linux"
  fi
  file_kernel="${bin_name}-${arch}"
  case "${bin_name}" in
    sing-box)
      # url_api="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
      # url_down="https://github.com/SagerNet/sing-box/releases/download"
      # sing_box_version_temp=$(wget --no-check-certificate -qO- "${url_download}" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
      # sing_box_version=${sing_box_version_temp:1}

      url_api="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
      url_down="https://github.com/SagerNet/sing-box/releases"
      sing_box_version_temp=$(wget --no-check-certificate -qO- "${url_api}" | grep '"tag_name":' | cut -d'"' -f4)
      sing_box_version=${sing_box_version_temp#v}

      download_link="${url_down}/download/${sing_box_version}/sing-box-${sing_box_version}-${platform}-${arch}.tar.gz"
      log debug "download ${download_link}"
      update_file "${data_dir}/${file_kernel}.tar.gz" "${download_link}"
      [ "$?" = "0" ] && kill_alive > /dev/null 2>&1
      ;;
    clash)
      if [ "${meta}" = "true" ] ; then
        download_link="https://github.com/taamarin/Clash.Meta/releases"
        local tag=$(wget --no-check-certificate -qO- ${download_link} | grep -oE 'tag\/([^"]+)' | cut -d '/' -f 2 | head -1)
        latest_version=$(wget --no-check-certificate -qO- "${download_link}/expanded_assets/${tag}" | grep -oE "alpha-[0-9,a-z]+" | head -1)
        filename="clash.meta-${platform}-${arch}"
        filename+="-cgo"
        filename+="-${latest_version}"
        log debug "download ${download_link}/download/${tag}/${filename}.gz"
        update_file "${data_dir}/${file_kernel}.gz" "${download_link}/download/${tag}/${filename}.gz"
      else
        if [ "${dev}" != "false" ] ; then
          download_link="https://release.dreamacro.workers.dev/latest"
          log debug "download ${download_link}/clash-linux-${arch}-latest.gz"
          update_file "${data_dir}/${file_kernel}.gz" "${download_link}/clash-linux-${arch}-latest.gz"
        else
          download_link="https://github.com/Dreamacro/clash/releases"
          filename=$(wget --no-check-certificate -qO- "${download_link}/expanded_assets/premium" | grep -oE "clash-linux-${arch}-[0-9]+.[0-9]+.[0-9]+" | head -1)
          log debug "download ${download_link}/download/premium/${filename}.gz"
          update_file "${data_dir}/${file_kernel}.gz" "${download_link}/download/premium/${filename}.gz"
        fi
      fi
      [ "$?" = "0" ] && kill_alive > /dev/null 2>&1
      ;;
    xray)
      download_link="https://github.com/XTLS/Xray-core/releases"
      github_api="https://api.github.com/repos/XTLS/Xray-core/releases"
      latest_version=$(wget --no-check-certificate -qO- ${github_api} | grep "tag_name" | grep -o "v[0-9.]*" | head -1)

      [ $(uname -m) != "aarch64" ] \
      && download_file="Xray-linux-arm32-v7a.zip" || download_file="Xray-android-arm64-v8a.zip"

      log debug "download ${download_link}/download/${latest_version}/${download_file}"
      update_file "${data_dir}/${file_kernel}.zip" "${download_link}/download/${latest_version}/${download_file}"
      [ "$?" = "0" ] && kill_alive > /dev/null 2>&1
    ;;
    v2fly)
      download_link="https://github.com/v2fly/v2ray-core/releases"
      github_api="https://api.github.com/repos/v2fly/v2ray-core/releases"
      latest_version=$(wget --no-check-certificate -qO- ${github_api} | grep "tag_name" | grep -o "v[0-9.]*" | head -1)

      [ $(uname -m) != "aarch64" ] \
      && download_file="v2ray-linux-arm32-v7a.zip" || download_file="v2ray-android-arm64-v8a.zip"

      log debug "download ${download_link}/download/${latest_version}/${download_file}"
      update_file "${data_dir}/${file_kernel}.zip" "${download_link}/download/${latest_version}/${download_file}"
      [ "$?" = "0" ] && kill_alive > /dev/null 2>&1
      ;;
    *)
      log error "kernel error." && exit 1
      ;;
  esac

  case "${bin_name}" in
    clash)
      if [ -f /system/bin/gunzip ]; then
        extra="/system/bin/gunzip"
      else
        extra="${busybox_path} gunzip"
      fi
      
      if ${extra} "${data_dir}/${file_kernel}.gz" >&2; then
        if mv -f "${data_dir}/${file_kernel}" "${bin_kernel}/${bin_name}"; then
          flag="true"
        else
          log error "failed to move the kernel"
        fi
      else
        log warn "failed to extract ${data_dir}/${file_kernel}.gz"
      fi
      
      if [ -f "${pid_file}" ] && [ "${flag}" = "true" ]; then
        restart_box
      else
        log debug "${bin_name} does not need to be restarted"
      fi
    ;;
    sing-box)
      if [ -f /system/bin/tar ]; then
        extra="/system/bin/tar"
      else
        extra="${busybox_path} tar"
      fi
      
      if ${extra} -xf "${data_dir}/${file_kernel}.tar.gz" -C "${data_dir}/bin" >&2; then
        if mv "${data_dir}/bin/sing-box-${sing_box_version}-${platform}-${arch}/sing-box" "${bin_kernel}/${bin_name}"; then
          flag="true"
          rm -r "${data_dir}/bin/sing-box-${sing_box_version}-${platform}-${arch}"
        else
          log error "failed to move the kernel"
        fi
      else
        log warn "failed to extract ${data_dir}/${file_kernel}.tar.gz"
      fi
      
      if [ -f "${pid_file}" ] && [ "${flag}" = "true" ]; then
        restart_box
      else
        log debug "${bin_name} does not need to be restarted"
      fi
    ;;
    v2fly)
      if [ -f /system/bin/unzip ]; then
        extra="/system/bin/unzip"
      else
        extra="${busybox_path} unzip"
      fi
      
      if ${extra} -o "${data_dir}/${file_kernel}.zip" "v2ray" -d "${bin_kernel}" >&2; then
        if mv "${bin_kernel}/v2ray" "${bin_kernel}/v2fly"; then
          flag="true"
        else
          log error "failed to move the kernel"
        fi
      else
        log warn "failed to extract ${data_dir}/${file_kernel}.zip"
      fi
      
      if [ -f "${pid_file}" ] && [ "${flag}" = "true" ]; then
        restart_box
      else
        log debug "${bin_name} does not need to be restarted"
      fi
    ;;
    xray)
      if [ -f /system/bin/unzip ]; then
        extra="/system/bin/unzip"
      else
        extra="${busybox_path} unzip"
      fi
      
      if ${extra} -o "${data_dir}/${file_kernel}.zip" "xray" -d "${bin_kernel}" >&2; then
        if mv "${bin_kernel}/xray" "${bin_kernel}/xray"; then
          flag="true"
        else
          log error "failed to move the kernel"
        fi
      else
        log warn "failed to extract ${data_dir}/${file_kernel}.zip"
      fi
      
      if [ -f "${pid_file}" ] && [ "${flag}" = "true" ]; then
        restart_box
      else
        log debug "${bin_name} does not need to be restarted"
      fi
    ;;
    *)
      log error "kernel error." && exit 1
    ;;
  esac

  chown ${box_user_group} ${bin_path}
  chmod 6755 ${bin_path}
}

# Function to limit cgroup memory
cgroup_limit() {
  # Check if cgroup_memory_limit is set
  if [ -z "${cgroup_memory_limit}" ]; then
    log warn "cgroup_memory_limit is not set"
    return 1
  fi

  # Check if cgroup_memory_path is set and exists
  if [ -z "${cgroup_memory_path}" ]; then
    local cgroup_memory_path=$(mount | grep cgroup | awk '/memory/{print $3}' | head -1)
    if [ -z "${cgroup_memory_path}" ]; then
      log warn "cgroup_memory_path is not set and cannot be found"
      return 1
    fi
  elif [ ! -d "${cgroup_memory_path}" ]; then
    log warn "${cgroup_memory_path} does not exist"
    return 1
  fi

  # Check if pid_file is set and exists
  if [ -z "${pid_file}" ]; then
    log warn "pid_file is not set"
    return 1
  elif [ ! -f "${pid_file}" ]; then
    log warn "${pid_file} does not exist"
    return 1
  fi

  # Create cgroup directory and move process to cgroup
  local bin_name=$(basename "$0")
  mkdir -p "${cgroup_memory_path}/${bin_name}"
  local pid=$(cat "${pid_file}")
  echo "${pid}" > "${cgroup_memory_path}/${bin_name}/cgroup.procs" \
    && log info "Moved process ${pid} to ${cgroup_memory_path}/${bin_name}/cgroup.procs"

  # Set memory limit for cgroup
  echo "${cgroup_memory_limit}" > "${cgroup_memory_path}/${bin_name}/memory.limit_in_bytes" \
    && log info "Set memory limit to ${cgroup_memory_limit} for ${cgroup_memory_path}/${bin_name}/memory.limit_in_bytes"

  return 0
}

update_dashboard() {
  network_check
  if [ "${bin_name}" = "sing-box" ] || [ "${bin_name}" = "clash" ]; then
    file_dashboard="${data_dir}/${bin_name}/dashboard.zip"
    rm -rf "${data_dir}/${bin_name}/dashboard/dist"
    url="https://github.com/MetaCubeX/Yacd-meta/archive/refs/heads/gh-pages.zip"
    dir_name="Yacd-meta-gh-pages"
    wget --no-check-certificate "${url}" -O "${file_dashboard}" 2>&1
    unzip -o "${file_dashboard}" "${dir_name}/*" -d "${data_dir}/${bin_name}/dashboard" >&2
    mv -f "${data_dir}/${bin_name}/dashboard/${dir_name}" "${data_dir}/${bin_name}/dashboard/dist"
    rm -f "${file_dashboard}"
  else
    log debug "${bin_name} does not support dashboards"
  fi
}

run_base64() {
  if [ "$(cat ${data_dir}/sing-box/acc.txt 2>&1)" != "" ] ; then
    log info "$(cat ${data_dir}/sing-box/acc.txt 2>&1)"
    base64 ${data_dir}/sing-box/acc.txt > ${data_dir}/dashboard/dist/proxy.txt
    log info "ceks ${data_dir}/dashboard/dist/proxy.txt"
    log info "done"
  else
    log warn "${data_dir}/sing-box/acc.txt is empty"
    exit 1
  fi
}

# copy bin ke system/bin
cp_bin() {
  if cp /data/adb/box/bin/* /data/adb/modules/box_for_magisk/system/bin; then
    log debug "File copy completed successfully."
  else
    log error "File copy failed."
  fi
}

reload() {
  if [ "${bin_name}" = "clash" ] || [ "${bin_name}" = "sing-box" ]; then
    case "${bin_name}" in
      sing-box)
        if ${bin_path} check -D "${data_dir}/${bin_name}" > "${run_path}/${bin_name}-report.log" 2>&1; then
          log info "config.json passed"
        else
          log error "config.json check failed"
          cat "${run_path}/${bin_name}-report.log"
          exit 1
        fi
        ;;
      clash)
        if ${bin_path} -t -d "${data_dir}/clash" -f "${clash_config}" > "${run_path}/${bin_name}-report.log" 2>&1; then
          log info "config.yaml passed"
        else
          log error "config.yaml check failed"
          cat "${run_path}/${bin_name}-report.log"
          exit 1
        fi
        ;;
      *)
        log error "Unknown binary: ${bin_name}"
        exit 1
        ;;
    esac
    log info "Open yacd-meta/configs and click 'Reload Configs'"
  else
    log error "This script is only for clash or sing-box binaries"
  fi
}

case "$1" in
  testing)
    testing
    ;;
  keepdns)
    keep_dns
    ;;
  connect)
    network_check
    ;;
  rbase64)
    run_base64
    ;;
  upyacd)
    update_dashboard
    ;;
  upcore)
    update_kernel
    ;;
  cgroup)
    cgroup_limit
    ;;
  port)
    port_detection
    ;;
  subgeo)
    update_subgeo
    find "${data_dir}/${bin_name}" -type f -name "*.db.bak" -delete
    find "${data_dir}/${bin_name}" -type f -name "*.dat.bak" -delete
    ;;
  reload)  
    reload
    ;;
  *)
    echo "$0: usage: $0 {reload|testing|keepdns|connect|rbase64|upyacd|upcore|cgroup|port|subgeo}"
    exit 1
    ;;
esac