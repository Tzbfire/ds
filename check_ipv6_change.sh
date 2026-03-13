#!/bin/sh

# 获取 eth0 的 IPv6 地址信息
ipv6_info=$(ip -6 addr show dev eth0 scope global dynamic 2>/dev/null)

# 检查是否有可用的 IPv6/64 地址
has_valid_ipv6=false

# 遍历每个全局动态 IPv6 地址
while IFS= read -r line; do
    # 匹配 IPv6 地址行（包含 /64）
    if echo "$line" | grep -q 'inet6.*/64.*scope global.*dynamic'; then
        # 提取地址部分
        addr=$(echo "$line" | awk '{print $2}' | cut -d'/' -f1)
        
        # 检查地址状态（非 deprecated 且 preferred_lft > 0）
        status=$(ip -6 addr show dev eth0 to "$addr" 2>/dev/null | grep -E 'inet6.*scope global.*dynamic')
        
        if echo "$status" | grep -q 'deprecated'; then
            echo "IPv6 地址 $addr 状态: deprecated (已弃用)"
            continue
        fi
        
        # 提取 preferred_lft 值
        pref_lft=$(echo "$status" | grep -o 'preferred_lft [0-9]*sec' | awk '{print $2}' | tr -d 'sec')
        
        if [ -n "$pref_lft" ] && [ "$pref_lft" -gt 0 ]; then
            echo "找到有效的 IPv6/64 地址: $addr/64 (preferred_lft: ${pref_lft}秒)"
            has_valid_ipv6=true
            # 可以退出循环，至少找到一个有效地址
            break
        else
            echo "IPv6 地址 $addr 状态: preferred_lft 为 0 或无效"
        fi
    fi
done <<EOF
$ipv6_info
EOF

# 根据检查结果执行操作
if [ "$has_valid_ipv6" = false ]; then
    echo "$(date): 未找到有效的 IPv6/64 地址，正在重启 WAN6 接口..."
    
    # 重启 WAN6 接口
    ifdown wan6
    sleep 2
    ifup wan6
    
    echo "WAN6 接口已重启"
    
    # 可选：重启后再次检查
    echo "重启后检查 IPv6 状态..."
    ip -6 addr show dev eth0 scope global dynamic 2>/dev/null | grep -E 'inet6.*/64.*scope global.*dynamic'
else
    echo "$(date): IPv6 连接正常"
fi
