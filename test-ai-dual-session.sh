#!/bin/bash
# ============================================================
# AI 双会话测试脚本
# 测试本地 AI 是否支持分析 + 文案生成两次会话
# ============================================================

# 配置 - 修改为你的本地 AI 地址和模型
AI_ENDPOINT="${AI_ENDPOINT:-http://localhost:11434}"
AI_MODEL="${AI_MODEL:-llava}"
TEST_IMAGE="${TEST_IMAGE:-/mnt/user/relive-photos/Earnest Phone/MIX2s/Camera/test.jpg}"

echo "=========================================="
echo "AI 双会话测试"
echo "=========================================="
echo "Endpoint: $AI_ENDPOINT"
echo "Model: $AI_MODEL"
echo "Test Image: $TEST_IMAGE"
echo ""

# 检查测试图片是否存在
if [ ! -f "$TEST_IMAGE" ]; then
    echo "❌ 测试图片不存在: $TEST_IMAGE"
    echo "请修改 TEST_IMAGE 变量为存在的照片路径"
    exit 1
fi

# 将图片转为 base64
IMAGE_BASE64=$(base64 -w 0 "$TEST_IMAGE")
echo "✓ 图片已编码 (长度: ${#IMAGE_BASE64})"
echo ""

# ============================================================
# 第一次会话：分析照片
# ============================================================
echo "=========================================="
echo "【第一次会话】照片分析"
echo "=========================================="

ANALYSIS_PROMPT='你是"个人相册照片评估助手"，擅长理解真实照片的内容，并从回忆价值和美观角度打分。
你会收到一张照片，你的任务是：
1）用中文详细描述照片内容（80-200字），包括人物、场景、活动、氛围等
2）判断照片的大致类型，必须从以下选项中只选其一（禁止使用英文）：人物/孩子/猫咪/家庭/旅行/风景/美食/宠物/日常/文档/杂物/截屏/其他
3）给出0-100的"值得回忆度"memory_score（精确到一位小数）
4）给出0-100的"美观程度"beauty_score（精确到一位小数）
5）给出3-8个标签，用逗号分隔，如：旅游,美食,家人,朋友,户外,室内
6）用简短中文reason解释原因（不超过40字）

请严格只输出 JSON，格式如下：
{
  "description": "详细描述照片内容（80-200字）",
  "main_category": "人物",
  "tags": "标签（逗号分隔），如：旅游,美食,家人,朋友,户外,室内",
  "memory_score": 85.0,
  "beauty_score": 88.0,
  "reason": "不超过40字的中文理由"
}'

echo "发送分析请求..."
ANALYSIS_RESPONSE=$(curl -s -X POST "$AI_ENDPOINT/api/generate" \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$AI_MODEL\",
        \"prompt\": \"$ANALYSIS_PROMPT\",
        \"images\": [\"$IMAGE_BASE64\"],
        \"stream\": false
    }" 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ 第一次会话请求失败"
    echo "请检查 AI 服务是否运行: $AI_ENDPOINT"
    exit 1
fi

echo "✓ 收到响应"
echo ""

# 提取响应内容（Ollama 格式）
ANALYSIS_TEXT=$(echo "$ANALYSIS_RESPONSE" | grep -o '"response":"[^"]*"' | sed 's/"response":"//;s/"$//' | sed 's/\\n/\n/g')

if [ -z "$ANALYSIS_TEXT" ]; then
    echo "⚠️ 无法提取响应内容，原始响应:"
    echo "$ANALYSIS_RESPONSE" | head -c 500
    echo ""
    exit 1
fi

echo "【分析结果】"
echo "----------------------------------------"
echo "$ANALYSIS_TEXT"
echo "----------------------------------------"
echo ""

# 提取 description 用于对比
DESCRIPTION=$(echo "$ANALYSIS_TEXT" | grep -o '"description":"[^"]*"' | head -1 | sed 's/"description":"//;s/"$//')
echo "提取到的 description: ${DESCRIPTION:0:50}..."
echo ""

# ============================================================
# 第二次会话：生成文案
# ============================================================
echo "=========================================="
echo "【第二次会话】文案生成"
echo "=========================================="

CAPTION_PROMPT='你是一位为「电子相框」撰写旁白短句的中文文案助手。
你的目标不是描述画面，而是为画面补上一点"画外之意"。

创作原则：
1. 避免使用以下词语：世界、梦、时光、岁月、温柔、治愈、刚刚好、悄悄、慢慢 等
2. 严禁使用如下句式：
   - 这是一张……
   - ……里……着整个世界/夏天
   - ……得像……（简单的比喻）
3. 只基于图片中能确定的信息进行联想，不要虚构时间、人物关系、事件背景
4. 文案应自然、有趣，带一点幽默或者诗意，但请避免煽情、鸡汤
5. 不要复述画面内容本身，而是写"看完画面后，心里多出来的一句话"
6. 可以偏向以下风格之一：
   - 日常中的微妙情绪
   - 轻微自嘲或冷幽默
   - 对时间、记忆、瞬间的含蓄感受
   - 看似平淡但有余味的一句判断

格式要求：
1. 只输出一句中文短句，不要换行，不要引号，不要任何解释
2. 建议长度8-24个汉字，最多不超过30个汉字
3. 不要出现"这张照片""这一刻""那天""这是一张"等指代照片本身的词

请为这张照片创作一句旁白短句：'

echo "发送文案生成请求..."
CAPTION_RESPONSE=$(curl -s -X POST "$AI_ENDPOINT/api/generate" \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$AI_MODEL\",
        \"prompt\": \"$CAPTION_PROMPT\",
        \"images\": [\"$IMAGE_BASE64\"],
        \"stream\": false
    }" 2>/dev/null)

if [ $? -ne 0 ]; then
    echo "❌ 第二次会话请求失败"
    exit 1
fi

echo "✓ 收到响应"
echo ""

# 提取文案响应
CAPTION_TEXT=$(echo "$CAPTION_RESPONSE" | grep -o '"response":"[^"]*"' | sed 's/"response":"//;s/"$//' | sed 's/\\n/\n/g')

if [ -z "$CAPTION_TEXT" ]; then
    echo "⚠️ 无法提取文案，原始响应:"
    echo "$CAPTION_RESPONSE" | head -c 500
    echo ""
    exit 1
fi

echo "【文案结果】"
echo "----------------------------------------"
echo "$CAPTION_TEXT"
echo "----------------------------------------"
echo ""

# ============================================================
# 结果对比
# ============================================================
echo "=========================================="
echo "【对比测试】"
echo "=========================================="

# 清理文案（移除引号、换行）
CAPTION_CLEAN=$(echo "$CAPTION_TEXT" | tr -d '"' | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

echo "Description (前50字): ${DESCRIPTION:0:50}"
echo "Caption: $CAPTION_CLEAN"
echo ""

# 判断是否相同
if [ "$CAPTION_CLEAN" = "${DESCRIPTION:0:${#CAPTION_CLEAN}}" ]; then
    echo "⚠️ 警告: Caption 与 Description 开头相同"
    echo "   可能 AI 没有正确理解第二次会话的意图"
else
    echo "✓ Caption 与 Description 不同，双会话正常工作"
fi

echo ""
echo "=========================================="
echo "测试完成"
echo "=========================================="
