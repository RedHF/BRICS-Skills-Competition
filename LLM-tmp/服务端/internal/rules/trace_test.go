package rules

import (
	"testing"
	"yanxia-server/internal/content"
)

func TestTraceRequiresContinuousOrderedDirectedStrokes(t *testing.T) {
	spec := &content.TraceSpec{Tolerance: .025, AspectRatio: 1, Strokes: [][][2]float64{{{.1, .2}, {.5, .2}}, {{.7, .2}, {.7, .6}}}}
	good := [][][2]float64{}
	for _, line := range spec.Strokes {
		points := [][2]float64{}
		for i := 0; i <= 20; i++ {
			f := float64(i) / 20
			points = append(points, [2]float64{line[0][0] + f*(line[1][0]-line[0][0]), line[0][1] + f*(line[1][1]-line[0][1])})
		}
		good = append(good, points)
	}
	if !MatchTrace(spec, good) {
		t.Fatal("valid tracing rejected")
	}
	cases := map[string][][][2]float64{"empty": {}, "missing_stroke": good[:1], "wrong_order": {good[1], good[0]}, "jump": {spec.Strokes[0], good[1]}}
	reversed := append([][2]float64{}, good[0]...)
	for i, j := 0, len(reversed)-1; i < j; i, j = i+1, j-1 {
		reversed[i], reversed[j] = reversed[j], reversed[i]
	}
	cases["reverse"] = [][][2]float64{reversed, good[1]}
	deviated := append([][2]float64{}, good[0]...)
	deviated[10][1] = .4
	cases["scribble"] = [][][2]float64{deviated, good[1]}
	cases["partial"] = [][][2]float64{good[0][:10], good[1]}
	for name, input := range cases {
		t.Run(name, func(t *testing.T) {
			if MatchTrace(spec, input) {
				t.Fatal("invalid trace accepted")
			}
		})
	}
}

func TestTraceAcceptsHumanDeviationInVisibleBand(t *testing.T) {
	spec := &content.TraceSpec{Tolerance: .10, AspectRatio: 2.4, Strokes: [][][2]float64{{{.2, .3}, {.7, .3}}}}
	// On a 264px-high canvas, 0.07 is about 18px of hand wobble.
	drawn := [][2]float64{}
	for i := 0; i <= 50; i++ {
		y := .3 + .07
		if i%2 == 0 {
			y = .3 + .055
		}
		drawn = append(drawn, [2]float64{.2 + float64(i)*.01, y})
	}
	if !MatchTrace(spec, [][][2]float64{drawn}) {
		t.Fatal("normal human deviation rejected")
	}
	for i := range drawn {
		drawn[i][1] = .42
	}
	if MatchTrace(spec, [][][2]float64{drawn}) {
		t.Fatal("drawing outside the visible band accepted")
	}
}
