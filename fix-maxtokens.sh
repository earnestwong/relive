#!/bin/bash
# 修复 Relive Caption 生成 max_tokens 限制

echo "=========================================="
echo "修复 Relive max_tokens 限制"
echo "=========================================="

# 进入容器并修改代码
docker exec -i relive sh << 'EOF'
echo "[1/3] 检查当前代码..."
grep -n 'max_tokens.*100' /app/internal/provider/openai.go

echo ""
echo "[2/3] 修改 max_tokens 为 65000..."
sed -i 's/"max_tokens":  *100/"max_tokens": 65000/' /app/internal/provider/openai.go

echo ""
echo "[3/3] 验证修改..."
grep -n 'max_tokens.*65000' /app/internal/provider/openai.go
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ 代码修改成功"
    echo ""
    echo "[4/4] 重启 Relive 容器..."
    docker restart relive
    echo ""
    echo "=========================================="
    echo "✓ 修复完成"
    echo "=========================================="
    echo ""
    echo "请等待容器重启完成（约 10-30 秒）"
    echo "然后重新分析照片测试 Caption 生成"
else
    echo ""
    echo "❌ 修改失败"
    exit 1
fi
