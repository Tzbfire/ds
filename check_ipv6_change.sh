#!/bin/sh

# 日志文件路径
LOG_FILE="/root/docker/ipv6_check.log"

# 记录日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
}

# 检查 eth0 是否有有效的 IPv6/64 地址
check_ipv6() {
    # 获取 eth0 的所有全局 IPv6 地址
    local ipv6_info=$(ip -6 addr show dev eth0 scope global 2>/dev/null)
    
    # 记录详细 IPv6 信息到日志
    log "详细 IPv6 信息:"
    echo "$ipv6_info" | while IFS= read -r line; do
        echo "  $line" >> "$LOG_FILE"
    done
    
    # 检查是否有非 deprecated 的 IPv6/64 地址
    local has_valid=0
    
    # 将输出按行处理
    echo "$ipv6_info" | while IFS= read -r line1; do
        # 查找 IPv6 地址行
        if echo "$line1" | grep -q 'inet6.*/64.*scope global'; then
            # 检查是否是 deprecated
            if echo "$line1" | grep -q 'deprecated'; then
                log "跳过弃用地址: $(echo "$line1" | awk '{print $2}')"
                continue
            fi
            
            # 读取下一行（包含 valid_lft 和 preferred_lft）
            if IFS= read -r line2; then
                # 检查 preferred_lft 是否大于 0
                if echo "$line2" | grep -q 'preferred_lft [1-9][0-9]*sec'; then
                    log "找到有效 IPv6 地址: $(echo "$line1" | awk '{print $2}')"
                    has_valid=1
                    echo "1" > /tmp/ipv6_check_result
                    break
                else
                    log "地址 $(echo "$line1" | awk '{print $2}') 的 preferred_lft 无效"
                fi
            fi
        fi
    done
    
    # 检查结果
    if [ -f /tmp/ipv6_check_result ]; then
        rm -f /tmp/ipv6_check_result
        return 0
    fi
    
    return 1
}

# 主程序
log "开始检查 IPv6 状态"

# 输出当前 IPv6 状态
log "当前 IPv6 状态摘要:"
ip -6 addr show dev eth0 scope global 2>/dev/null | grep -A1 'inet6.*/64.*scope global' | while IFS= read -r line; do
    echo "  $line" >> "$LOG_FILE"
done

if check_ipv6; then
    log "IPv6 连接正常"
    exit 0
else
    log "未找到有效的 IPv6/64 地址，正在重启 WAN6 接口..."
    
    # 重启 WAN6 接口
    ifdown wan6
    sleep 2
    ifup wan6
    
    log "WAN6 接口已重启"
    
    # 重启后检查状态
    sleep 3
    log "重启后 IPv6 状态:"
    ip -6 addr show dev eth0 scope global 2>/dev/null | while IFS= read -r line; do
        echo "  $line" >> "$LOG_FILE"
    done
    
    exit 1
fi
