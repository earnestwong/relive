package geocode

import (
	"math"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestHaversineDistance_SamePoint(t *testing.T) {
	dist := haversineDistance(39.9042, 116.4074, 39.9042, 116.4074)
	assert.Equal(t, 0.0, dist)
}

func TestHaversineDistance_KnownCityPair(t *testing.T) {
	// Beijing to Shanghai: ~1068 km
	dist := haversineDistance(39.9042, 116.4074, 31.2304, 121.4737)
	assert.InDelta(t, 1068, dist, 15) // within 15km tolerance
}

func TestHaversineDistance_Symmetry(t *testing.T) {
	d1 := haversineDistance(39.9042, 116.4074, 35.6762, 139.6503)
	d2 := haversineDistance(35.6762, 139.6503, 39.9042, 116.4074)
	assert.InDelta(t, d1, d2, 0.001)
}

func TestHaversineDistance_Antipodal(t *testing.T) {
	// Opposite sides of Earth: should be ~half circumference
	dist := haversineDistance(0, 0, 0, 180)
	halfCircumference := math.Pi * 6371.0
	assert.InDelta(t, halfCircumference, dist, 1)
}

func TestHaversineDistance_CrossEquator(t *testing.T) {
	// Singapore to Sydney: ~6300 km
	dist := haversineDistance(1.3521, 103.8198, -33.8688, 151.2093)
	assert.InDelta(t, 6300, dist, 50)
}

// ===== Helper functions =====

func TestGetCountryName_Known(t *testing.T) {
	assert.Equal(t, "中国", getCountryName("CN"))
	assert.Equal(t, "日本", getCountryName("JP"))
}

func TestGetCountryName_Unknown(t *testing.T) {
	assert.Equal(t, "XX", getCountryName("XX"))
}

func TestGetProvinceName_China(t *testing.T) {
	// 验证修正后的省份映射
	assert.Equal(t, "安徽省", getProvinceName("CN", "01"))  // 01 → 安徽
	assert.Equal(t, "上海市", getProvinceName("CN", "23"))  // 23 → 上海
	assert.Equal(t, "贵州省", getProvinceName("CN", "18"))  // 18 → 贵州（原版错误映射为辽宁）
	assert.Equal(t, "辽宁省", getProvinceName("CN", "19"))  // 19 → 辽宁（原版错误映射为海南）
	assert.Equal(t, "海南省", getProvinceName("CN", "31"))  // 31 → 海南（原版错误映射为四川）
	assert.Equal(t, "四川省", getProvinceName("CN", "32"))  // 32 → 四川（原版错误映射为重庆）
	assert.Equal(t, "重庆市", getProvinceName("CN", "33"))  // 33 → 重庆（原版错误映射为香港）
}

func TestGetProvinceName_NonChina(t *testing.T) {
	assert.Equal(t, "California", getProvinceName("US", "California"))
}
