#!/bin/sh

# 日志文件路径
LOG_FILE="/root/docker/ipv6_check.log"
MAX_LOG_LINES=1000

# 记录日志函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" | tee -a "$LOG_FILE"
}

# 限制日志文件大小
limit_log_size() {
    if [ -f "$LOG_FILE" ]; then
        # 计算当前行数
        local line_count=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
        
        # 如果超过最大行数，只保留最后1000行
        if [ "$line_count" -gt "$MAX_LOG_LINES" ]; then
            log "日志文件超过 ${MAX_LOG_LINES} 行，正在清理..."
            local temp_file="${LOG_FILE}.tmp"
            
            # 保留最后1000行
            tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "$temp_file"
            
            # 替换原文件
            mv "$temp_file" "$LOG_FILE"
            
            log "日志文件已清理，保留最新的 ${MAX_LOG_LINES} 行"
        fi
    fi
}

# 检查 eth0 是否有有效的 IPv6/64 地址
check_ipv6() {
    # 获取 eth0 的所有全局 IPv6 地址
    local ipv6_info=$(ip -6 addr show dev eth0 scope global 2>/dev/null)
    
    # 简化日志：只记录IPv6地址相关的关键信息
    log "当前IPv6地址状态:"
    
    # 只提取并记录IPv6地址信息
    echo "$ipv6_info" | grep -A2 'inet6.*/64.*scope global' | while IFS= read -r line; do
        # 跳过空行和接口信息行
        if echo "$line" | grep -q 'inet6' || echo "$line" | grep -q 'valid_lft\|preferred_lft'; then
            echo "  $line" >> "$LOG_FILE"
        fi
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
# 先限制日志大小
limit_log_size

log "开始检查 IPv6 状态"

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
    log "重启后 IPv6 地址状态:"
    ip -6 addr show dev eth0 scope global 2>/dev/null | grep -A2 'inet6.*/64.*scope global' | while IFS= read -r line; do
        if echo "$line" | grep -q 'inet6' || echo "$line" | grep -q 'valid_lft\|preferred_lft'; then
            echo "  $line" >> "$LOG_FILE"
        fi
    done
    
    exit 1
fi
