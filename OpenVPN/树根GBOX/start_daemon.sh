#!/bin/sh

if [ ! -f /tmp/start_daemon.pid ]; then
        echo 1 >/tmp/start_daemon.pid
else
        echo "start_daemon.sh is on running, exit"
        exit 0
fi

#执行一次
#/opt/part.sh
#sleep 1
mv /opt/part.sh /opt/omit_part.sh
sync

make_install() {
        tar_gz_name=$1
        curr_dir=$(pwd)
        temp_dir=$(mktemp -d)

        # 解压gz
        cp "${tar_gz_name}" "${temp_dir}"/
        cd ${temp_dir} || exit

        ota_tar_name=$(/bin/ls)
        tar xvf "${ota_tar_name}"
        if [ $? -ne 0 ]; then
                # 文件格式不正确
                rm -rf "${temp_dir}"
                cd ${curr_dir} || exit
                return 2
        fi

        rm -f "${ota_tar_name}"
        ota_tar_dir=$(/bin/ls)
        if [ "${ota_tar_dir}"x == ""x -o ! -d "${ota_tar_dir}" ]; then
                # tar没解压开
                rm -rf "${temp_dir}"
                cd ${curr_dir} || exit
                return 2
        fi

        # 开始安装更新
        if [ ! -f "${ota_tar_dir}"/install_update.sh ]; then
                rm -rf "${temp_dir}"
                cd ${curr_dir} || exit
                return 2
        fi
        chmod 755 "${ota_tar_dir}"/install_update.sh
        cd "${temp_dir}"/${ota_tar_dir} || exit

        if [ ! -f ssh_pk_lists ]; then
                #kill `pidof entryMain canApp gpsApp led_blink.sh mount_usb.sh`
                #killall entryMain canApp gpsApp led_blink.sh mount_usb.sh
                ./install_update.sh
                #./install_update.sh --action update
        else
                echo "it is not open ir_ota package,upgrade fail"
        fi
        sync
        rm -rf "${temp_dir}"
        cd ${curr_dir} || exit
        rm -f "${ota_file_path}"
}

update_endpoints() {
    # 读取 /media/sdcard/erk-root/endpoints.json 文件中的 username 和 password 值
    current_username=$(grep '"username":' /media/sdcard/erk-root/endpoints.json | awk -F: '{print $2}' | sed 's/[", ]//g')
    current_password=$(grep '"password":' /media/sdcard/erk-root/endpoints.json | awk -F: '{print $2}' | sed 's/[", ]//g')

    # 检查 username 和 password 是否为预期值
    if [ "$current_username" = "token-auth" ] || [ "$current_password" = "demoToken" ]; then
        id=$(cat /opt/conf.ini | grep id | awk -F = '{printf $2}' | sed 's/ //g')
        secret=$(cat /opt/conf.ini | grep secret | awk -F = '{printf $2}' | sed 's/ //g')

        # 如果是，则更新这些值
        sed -i 's/"username"[^,]*/"username": '\"${id}\"'/' /media/sdcard/erk-root/endpoints.json
        sed -i 's/"password"[^,]*/"password": '\"${secret}\"'/' /media/sdcard/erk-root/endpoints.json
    fi
}

# 检查指定目录下是否存在大小为0的文件
check_empty_files() {
    local directory=$1  # 获取函数的第一个参数作为目录路径

    # 检查是否提供了目录参数
    if [[ -z "$directory" ]]; then
        echo "Usage: check_empty_files [directory]"
        return 0  # 没有提供参数，视为非错误的情形，返回0
    fi

    # 检查目录是否存在
    if [[ ! -d "$directory" ]]; then
        echo "Directory does not exist: $directory"
        return 0  # 目录不存在，同样视为非错误的情形，返回0
    fi

    # 使用find命令搜索目录下所有大小为0的文件
    local empty_files=$(find "$directory" -type f -size 0)

    # 检查是否找到了大小为0的文件
    if [[ -n "$empty_files" ]]; then
        echo "Found empty files in '$directory':"
        echo "$empty_files"
        return 1  # 找到大小为0的文件，返回1
    else
        echo "No empty files found in '$directory'."
        return 0  # 没有找到大小为0的文件，返回0
    fi
}

#目录定义
erk_dir="/media/sdcard/erk-root/"
done_dir="/opt"
current_date=$(date +"%Y-%m-%d")
done_file="$done_dir/install_done_$current_date"
dest_dir_tool="/media/sdcard/erk-root/tools"

install_newc() {
    local image_dir="/media/sdcard/erk-root/images"
    local agent_dir="/NVM/oem_data/erk-agent"
    local conf_ini="/opt/conf.ini"    
#     local erk_dir="/media/sdcard/erk-root/"
#     local current_date=$(date +"%Y-%m-%d")
#     local done_dir="/opt"
#     local done_file="$done_dir/install_done_$current_date"
    
    mkdir -p $image_dir

    # 动态匹配文件名
    local agent_tar=$(find /NVM/oem_data/ -type f -name 'erk-agent*.tar.gz' | head -n 1)

    # 检查是否存在 conf.ini
    if [ -f "$conf_ini" ]; then
        # 检查 /opt/images 目录中是否存在文件 install_done**
        if [ -z "$(ls $done_dir/install_done*)" ]; then
            echo "No install_done file found. Proceeding with installation."

            #先删除原来的安装文件
            rm -rf $erk_dir
            mkdir -p $image_dir

            # 解压代理文件
            tar -xzvf "$agent_tar" -C "$image_dir"

            # 动态设置解压后的目录名
            local extracted_dir=$(basename "$agent_tar" .tar.gz)

            # 切换到解压后的代理目录
            cd "$image_dir"/"$extracted_dir"

            # 执行 install.sh 脚本
            ./install.sh

            update_endpoints

            #检查是否存在空文件，存在说明安装失败（不考虑源文件的问题）
            check_empty_files "$erk_dir"
            result=$?
            if [[ $result -eq 1 ]]; then
                echo "Action needed: there are empty files."
                rm $done_dir/install_done*
            else
                echo "All install success."
                # 安装完成后创建 install_done_年-月-日 文件
                touch "$done_file"            
            fi
        elif [ ! -f "$erk_dir/erk-daemon.sh" ]; then
            echo "Action needed: there are empty files."
            rm $done_dir/install_done*
        else
            echo "Found an install_done file. No installation needed."
        fi
    else
        echo "conf.ini not found. No installation needed."
    fi
}

install_stub_tools() {
    local agent_tar_dir="/NVM/oem_data/"
    local temp_dir="/media/sdcard/temp_erk_extract"
    local dest_dir="/media/sdcard/erk-root/tools_new"
    local agent_tar_path=$(find "$agent_tar_dir" -type f -name 'erk-agent*.tar.gz' | head -n 1)
    local agent_tar_with_extension=$(basename "$agent_tar_path")
    local agent_tar_file="${agent_tar_with_extension%.tar.gz}"

    if [ -z "$agent_tar_path" ]; then
        echo "No erk-agent*.tar.gz file found in $agent_tar_dir."
        return 1
    fi

    rm -rf /media/sdcard/tools_bak
    mv "$dest_dir_tool" /media/sdcard/tools_bak
    sleep 1

    # 创建临时解压目录
    mkdir -p "$temp_dir"
    # 创建最终的 tools 目录
    # mkdir -p "$dest_dir"

    # 解压 tar 包到临时目录
    tar -xzvf "$agent_tar_path" -C "$temp_dir"

    # 检查是否解压成功
    if [ $? -ne 0 ]; then
        echo "Failed to extract the tar file."
        return 1
    fi

    # 将 tools 目录下的所有文件复制到目标目录，如果已经存在，则跳过
    if [ -d "$temp_dir/$agent_tar_file/tools" ]; then
        # 使用 cp 命令进行复制，-n 选项避免覆盖目标目录中已存在的文件 
        mv "$temp_dir/$agent_tar_file/tools" "$dest_dir"
        sleep 3
        sync
    else
        echo $temp_dir/$agent_tar_file/tools
        echo "No tools directory found after extraction."
        return 1
    fi

    # 清理临时解压目录
    rm -rf "$temp_dir"
    echo "Tools have been successfully extracted to $dest_dir."
}

####### end 安装新C

ota_file_path=/usrdata/ir_ota.tar.gz

mount_success=0
dev_path="/dev/mmcblk0p1"

#mkdir -p /media/sdcard

echo 3 > /proc/sys/vm/drop_caches
sleep 1
#install_newc
# 目录路径定义在前面
# 检查目录是否存在
if [[ -d "$dest_dir_tool" ]]; then
    check_empty_files "$dest_dir_tool"
    result=$?
    if [[ $result -eq 1 ]]; then
        echo "Action needed: there are empty files in tools"
        echo 3 > /proc/sys/vm/drop_caches
        sleep 1
        #install_stub_tools  #重新安装tools
        #install_newc  #重新安装新C
    fi
fi
##########END NEWC CHECK############

/opt/mount_usb.sh &
/opt/led_blink.sh &
# /media/sdcard/erk-root/erk-daemon.sh &
# /opt/doftp.sh &
#检查更新endpoints
#update_endpoints
# 检查 /media/sdcard/erk-root/erk-daemon.sh 是否存在
if [ -f "/media/sdcard/erk-root/erk-daemon.sh" ]; then
    echo "erk-daemon.sh exists, executing..."
    # 执行脚本并将其放入后台运行
    #/media/sdcard/erk-root/erk-daemon.sh &
else
    echo "erk-daemon.sh does not exist, skipping execution."
fi

#/usr/dial/dial &
for i in $(seq 1 10); do
        pppNum=$(ifconfig | grep ccinet | grep -v grep | wc -l)
        if [ "$pppNum" -ge 1 ]; then
                echo "4G_network_connected"
                break
        fi
        sleep 1
done

if [ ! -f /opt/conf.ini ]; then
        chmod 755 /opt/factoryApp
#        /opt/factoryApp &
fi

/opt/mosquitto -c /opt/mosquitto.conf >/dev/null 2>&1 &

#/usr/bin/io_mng >/dev/null 2>&1 &
#sleep 3 #wait for io_mng to get MCU time.
/usr/bin/sw_mng >/dev/null 2>&1 &
/usr/bin/mosquitto &

# chmod 755 /opt/gb_32960_client
# /opt/gb_32960_client >/dev/null 2>&1 &

# chmod 755 /opt/ciu98_mng
# /opt/ciu98_mng >/dev/null 2>&1 &

#killall -9 truckCrane_dataRecorder
#/opt/truckCrane_dataRecorder >/dev/null 2>&1 &

#killall -9 syifm
#/opt/syifm >/dev/null 2>&1 &

#/opt/typeApp >/dev/null 2>&1 &

atc_uart &

while true; do
        #echo "enter_while_loop"
        #if ota, update file first 更新
        if [ -f "${ota_file_path}" ]; then
                echo "find_new_ota,reboot to install"
                make_install ${ota_file_path}
                rm -f ${ota_file_path}
                sync
                sleep 10
                reboot
        fi

        #excute_device_apps
        #monitor_device_apps

	alive=$(ps w | grep mosquitto | grep -v grep | wc -l)
	if [ $alive -eq 0 ]; then
		if [ -f "/usr/bin/mosquitto" ]; then
			echo "start mosquitto.."
			chmod +x /usr/bin/mosquitto
			killall -9 mosquitto
			/usr/bin/mosquitto &
		fi
        fi

        #execute io_mng if exist
        alive=$(ps w | grep io_mng | grep -v grep | wc -l)
        if [ "$alive" -eq 0 ]; then
                if [ -f "/usr/bin/io_mng" ]; then
                        chmod +x /usr/bin/io_mng
                        #/usr/bin/io_mng >/dev/null 2>&1 &
                fi
        fi

	alive=$(ps w | grep sw_mng | grep -v grep | wc -l)
	if [ $alive -eq 0 ]; then
		if [ -f "/usr/bin/sw_mng" ]; then
			chmod +x /usr/bin/sw_mng
			#/usr/bin/sw_mng >/dev/null 2>&1 &
		fi
	fi

    pppNum=$(ifconfig | grep ccinet | grep -v grep | wc -l)
    if [ "$pppNum" -eq 0 ]; then
        echo "4G_network_disconnected"
        ql_netcall -p 1 -r 5 -d &
    fi

    sleep 30
done
