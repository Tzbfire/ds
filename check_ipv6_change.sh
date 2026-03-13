#!/bin/sh

# 检查 eth0 接口是否有有效的 IPv6/64 地址
check_ipv6() {
    # 获取 eth0 接口的所有 IPv6 全局地址
    local ipv6_output=$(ip -6 addr show dev eth0 scope global 2>/dev/null)
    
    # 检查是否有至少一个非 deprecated 的 IPv6/64 地址
    local valid_found=0
    
    # 使用 while 循环处理每一行
    echo "$ipv6_output" | while IFS= read -r line; do
        # 检查是否是 IPv6 地址行
        if echo "$line" | grep -q 'inet6.*/64.*scope global'; then
            # 提取整个地址块
            local addr_line="$line"
            # 读取下一行（续行）
            IFS= read -r next_line
            # 检查是否是 deprecated 状态
            if echo "$addr_line" | grep -q 'deprecated'; then
                echo "跳过 deprecated 地址: $(echo "$addr_line" | awk '{print $2}')"
                continue
            elif echo "$next_line" | grep -q 'preferred_lft 0sec'; then
                echo "跳过 preferred_lft=0 的地址: $(echo "$addr_line" | awk '{print $2}')"
                continue
            else
                # 检查 preferred_lft 是否大于 0
                local pref_lft=$(echo "$next_line" | grep -o 'preferred_lft [0-9]*sec' | awk '{print $2}' | tr -d 'sec')
                if [ -n "$pref_lft" ] && [ "$pref_lft" -gt 0 ]; then
                    echo "找到有效 IPv6/64 地址: $(echo "$addr_line" | awk '{print $2}') (preferred_lft: ${pref_lft}秒)"
                    valid_found=1
                    break
                fi
            fi
        fi
    done
    
    return $valid_found
}

# 主逻辑
echo "$(date): 开始检查 IPv6 状态..."

# 检查是否有有效 IPv6 地址
if check_ipv6; then
    echo "$(date): IPv6 连接正常"
    exit 0
else
    echo "$(date): 未找到有效的 IPv6/64 地址，正在重启 WAN6 接口..."
    
    # 重启 WAN6 接口
    ifdown wan6
    sleep 2
    ifup wan6
    
    echo "WAN6 接口已重启"
    
    # 等待一段时间让接口重新获取地址
    sleep 5
    
    # 重启后再次检查
    echo "重启后检查 IPv6 状态..."
    ip -6 addr show dev eth0 scope global 2>/dev/null
    exit 1
fi
