package rules

import (
	"math"
	"yanxia-server/internal/content"
)

// MatchTrace checks raw pointer samples, never a client-reported completion flag.
// Strokes must follow their authored order and direction, without jumping gaps.
func MatchTrace(spec *content.TraceSpec, strokes [][][2]float64) bool {
	if len(strokes) != len(spec.Strokes) {
		return false
	}
	total := 0
	for i, drawn := range strokes {
		total += len(drawn)
		if len(drawn) < 2 || total > 8192 {
			return false
		}
		guide := append([][2]float64{}, spec.Strokes[i]...)
		for j := range guide {
			guide[j][0] *= spec.AspectRatio
		}
		lengths := make([]float64, len(guide))
		for j := 1; j < len(guide); j++ {
			lengths[j] = lengths[j-1] + math.Hypot(guide[j][0]-guide[j-1][0], guide[j][1]-guide[j-1][1])
		}
		previous := 0.0
		for j, p := range drawn {
			if math.IsNaN(p[0]) || math.IsNaN(p[1]) || math.IsInf(p[0], 0) || math.IsInf(p[1], 0) || p[0] < 0 || p[0] > 1 || p[1] < 0 || p[1] > 1 {
				return false
			}
			if j > 0 && math.Hypot((p[0]-drawn[j-1][0])*spec.AspectRatio, p[1]-drawn[j-1][1]) > .12 {
				return false
			}
			p[0] *= spec.AspectRatio
			best, progress := math.Inf(1), 0.0
			for k := 1; k < len(guide); k++ {
				a, b := guide[k-1], guide[k]
				dx, dy := b[0]-a[0], b[1]-a[1]
				t := math.Max(0, math.Min(1, ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/(dx*dx+dy*dy)))
				distance := math.Hypot(p[0]-a[0]-t*dx, p[1]-a[1]-t*dy)
				if distance < best {
					best = distance
					progress = lengths[k-1] + t*(lengths[k]-lengths[k-1])
				}
			}
			if best > spec.Tolerance || progress < previous-spec.Tolerance || (j == 0 && progress > spec.Tolerance) {
				return false
			}
			previous = math.Max(previous, progress)
		}
		if previous < lengths[len(lengths)-1]-spec.Tolerance {
			return false
		}
	}
	return true
}
