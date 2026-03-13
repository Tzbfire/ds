#!/bin/sh

# 更简单的方法：直接检查是否有非 deprecated 且 preferred_lft > 0 的 IPv6/64 地址
check_ipv6_simple() {
    # 获取所有全局 IPv6 地址
    ip -6 addr show dev eth0 scope global 2>/dev/null | \
    awk '/inet6.*\/64.*scope global/ && !/deprecated/ {
        getline next_line
        if (next_line ~ /preferred_lft [1-9][0-9]*sec/) {
            print "找到有效 IPv6 地址"
            exit 0
        }
    } END {
        if (NR == 0) exit 1
        exit 1
    }'
    
    return $?
}

# 或者使用这个更可靠的方法
check_ipv6_reliable() {
    # 使用 ip -j 输出 JSON 格式（如果支持）
    if ip -j -6 addr show dev eth0 scope global 2>/dev/null >/dev/null 2>&1; then
        # 支持 JSON 输出
        local has_valid=$(ip -j -6 addr show dev eth0 scope global 2>/dev/null | \
            jq -r '.[].addr_info[] | select(.prefixlen==64 and .scope=="global" and .valid_life_time>0 and .preferred_life_time>0) | .local' | head -1)
        
        if [ -n "$has_valid" ]; then
            echo "找到有效 IPv6 地址: $has_valid/64"
            return 0
        fi
    else
        # 不支持 JSON，使用文本解析
        local output=$(ip -6 addr show dev eth0 scope global 2>/dev/null)
        
        # 将输出按地址块分割处理
        echo "$output" | awk '
        BEGIN { valid=0 }
        /inet6.*\/64.*scope global/ {
            # 保存当前地址行
            addr_line=$0
            # 检查是否包含 deprecated
            if ($0 ~ /deprecated/) {
                next
            }
            # 读取续行
            getline
            if ($0 ~ /preferred_lft 0sec/) {
                next
            }
            # 检查 preferred_lft 是否大于 0
            if (match($0, /preferred_lft ([0-9]+)sec/, arr) && arr[1] > 0) {
                valid=1
                print "找到有效 IPv6 地址"
                exit
            }
        }
        END { if (!valid) exit 1 }'
        
        return $?
    fi
    
    return 1
}

# 主逻辑
echo "$(date): 开始检查 IPv6 状态..."

# 检查是否有有效 IPv6 地址
if check_ipv6_reliable; then
    echo "$(date): IPv6 连接正常"
    exit 0
else
    echo "$(date): 未找到有效的 IPv6/64 地址，正在重启 WAN6 接口..."
    
    # 记录日志
    logger -t ipv6-check "没有有效 IPv6 地址，重启 WAN6 接口"
    
    # 重启 WAN6 接口
    ifdown wan6
    sleep 2
    ifup wan6
    
    echo "WAN6 接口已重启"
    
    # 等待一段时间让接口重新获取地址
    sleep 10
    
    # 重启后再次检查并记录
    echo "重启后检查 IPv6 状态..."
    ip -6 addr show dev eth0 scope global 2>/dev/null
    
    # 记录到系统日志
    logger -t ipv6-check "WAN6 接口已重启，当前 IPv6 状态:"
    ip -6 addr show dev eth0 scope global 2>/dev/null | logger -t ipv6-check
    
    exit 1
fi
