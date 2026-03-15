#!/bin/sh
# OpenWrt 免安装实时网速监控 (单位: Mbps)
# 公式: (字节差值 * 8 bit) / 1024 / 1024 / 时间间隔(2s)

echo "正在监控网络接口... (按 Ctrl+C 退出)"
echo "----------------------------------------------------------------"
printf "%-12s %15s %15s\n" "接口" "↓ 下载 (Mbps)" "↑ 上传 (Mbps)"
echo "----------------------------------------------------------------"

# 初始化：读取第一次数值
prev_data=$(cat /proc/net/dev | tail -n +3)

while true; do
    sleep 2  # 采样间隔 2 秒
    
    # 读取第二次数值
    curr_data=$(cat /proc/net/dev | tail -n +3)
    
    # 使用 awk 进行差值计算
    echo "$prev_data" | awk -v curr="$curr_data" '
    BEGIN {
        # 解析当前数据存入数组
        n = split(curr, lines, "\n")
        for (i = 1; i <= n; i++) {
            if (lines[i] == "") continue
            split(lines[i], fields)
            gsub(/:/, "", fields[1]) # 去除冒号
            iface = fields[1]
            curr_rx[iface] = fields[2]
            curr_tx[iface] = fields[10]
        }
    }
    {
        # 处理上一次的数据 (来自 stdin)
        gsub(/:/, "", $1)
        iface = $1
        prev_rx = $2
        prev_tx = $10
        
        # 如果当前数据里没有这个接口（比如刚拔了线），跳过
        if (!(iface in curr_rx)) next

        # 计算差值 (字节)
        diff_rx = curr_rx[iface] - prev_rx
        diff_tx = curr_tx[iface] - prev_tx
        
        # 防止接口重置导致负数
        if (diff_rx < 0) diff_rx = 0
        if (diff_tx < 0) diff_tx = 0
        
        # 转换为 Mbps: (字节 * 8) / 1024 / 1024 / 2秒
        # 简化常数: 8 / 1024 / 1024 / 2 = 1 / 262144
        speed_rx = diff_rx / 262144
        speed_tx = diff_tx / 262144
        
        # 格式化输出 (保留2位小数)
        printf "%-12s %15.2f %15.2f\n", iface, speed_rx, speed_tx
    }'
    
    # 更新旧数据
    prev_data="$curr_data"
done
