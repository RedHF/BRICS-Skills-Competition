package content

import "fmt"

type EchoStageSpec struct {
	Kind        string       `json:"kind"`
	Goal        string       `json:"goal"`
	Background  string       `json:"background"`
	Objects     []EchoObject `json:"objects"`
	Pieces      []EchoPiece  `json:"pieces,omitempty"`
	DryArea     [][2]float64 `json:"dry_area,omitempty"`
	BlockedArea [4]float64   `json:"blocked_area,omitempty"`
	Rubbing     *RubbingSpec `json:"rubbing,omitempty"`
}

type EchoObject struct {
	ID       string     `json:"id"`
	Label    string     `json:"label"`
	Position [2]float64 `json:"position"`
	StepID   string     `json:"step_id,omitempty"`
	Text     string     `json:"text,omitempty"`
}

type EchoPiece struct {
	ID              string `json:"id"`
	Label           string `json:"label"`
	Texture         string `json:"texture"`
	Mark            string `json:"mark"`
	InitialRotation int    `json:"initial_rotation"`
	Description     string `json:"description"`
}

// Region geometry is shared so visual progress and authoritative coverage use
// the same paper coordinates. It describes the visible motif, not an answer key.
type RubbingSpec struct {
	Texture     string          `json:"texture"`
	BrushRadius float64         `json:"brush_radius"`
	Threshold   float64         `json:"threshold"`
	Resolution  int             `json:"resolution"`
	Regions     []RubbingRegion `json:"regions"`
}

type RubbingRegion struct {
	ID     string     `json:"id"`
	Label  string     `json:"label"`
	Shape  string     `json:"shape"`
	Center [2]float64 `json:"center"`
	Inner  float64    `json:"inner,omitempty"`
	Outer  float64    `json:"outer,omitempty"`
	Rect   [4]float64 `json:"rect,omitempty"`
}

func configureTempleStage(event *Event) {
	switch event.ID {
	case "temple_incense":
		event.Puzzle.Type = "echo_joinery"
		event.Puzzle.Dependencies = true
		event.Puzzle.Steps = []PuzzleStep{
			{ID: "inspect_join", Kind: "observe", Prompt: "看看梁端的榫口。", Answer: "join", Points: 0},
			{ID: "inspect_marks", Kind: "observe", Prompt: "看看梁上余料的记号。", Answer: "marks", Points: 0},
			{ID: "hall_support", Kind: "skill", Prompt: "让梁先稳下来。", Answer: "斗拱", Target: "beam", Requires: []string{"inspect_join", "inspect_marks"}, Points: 10},
			{ID: "hall_left", Kind: "joinery", Prompt: "比对榫口与木件。", Answer: "JOIN-L", Target: "SLOT-L", Rotation: 180, Requires: []string{"hall_support"}, Points: 25},
			{ID: "hall_right", Kind: "joinery", Prompt: "比对另一端的接合处。", Answer: "JOIN-R", Target: "SLOT-R", Requires: []string{"hall_support"}, Points: 25},
			{ID: "hall_center", Kind: "joinery", Prompt: "让两端在中部合拢。", Answer: "JOIN-C", Target: "SLOT-C", Requires: []string{"hall_left", "hall_right"}, Points: 30},
			{ID: "hall_release", Kind: "action", Prompt: "试着撤下临撑。", Answer: "release", Target: "support", Requires: []string{"hall_center"}, Points: 10},
		}
		event.Stage = &EchoStageSpec{Kind: "joinery", Goal: "读懂榫口与记号，让这根梁重新合拢。", Background: "res://assets/echo_v1/temple_hall_master.png",
			Objects: []EchoObject{
				{ID: "join", Label: "梁端榫口", Position: [2]float64{.27, .29}, StepID: "inspect_join", Text: "凸榫与凹口互相咬合；左右两处留下不同记号。先看接合处，再决定怎样装。"},
				{ID: "marks", Label: "余料记号", Position: [2]float64{.69, .20}, StepID: "inspect_marks", Text: "梁上留着双短痕、一道斜痕与中央合拢痕，来自不同人家的木料。它们要彼此接住，不靠木色判断。"},
				{ID: "beam", Label: "临时承架", Position: [2]float64{.49, .61}},
			}, Pieces: []EchoPiece{
				{ID: "JOIN-L", Label: "双短痕木件", Texture: "res://assets/puzzles/tenon_piece.png", Mark: "||", InitialRotation: 0, Description: "一侧有凸榫，肩部留着两道短痕。转过来看看另一端。"},
				{ID: "JOIN-R", Label: "斜痕木件", Texture: "res://assets/puzzles/tenon_piece.png", Mark: "/", Description: "肩部留一道斜痕，与另一处凹口的方向不同。"},
				{ID: "JOIN-C", Label: "中部合拢件", Texture: "res://assets/puzzles/dougong_bracket.png", Mark: "=", Description: "两端都有接合轮廓，需要两侧先就位。"},
				{ID: "JOIN-X", Label: "旧木件", Texture: "res://assets/puzzles/tenon_piece.png", Mark: "×", Description: "榫头缺了一角。记录它的旧痕，别把缺损硬塞进梁口。"},
			}}
		event.Investigations = []InvestigationSpec{{Label: "梁端榫口", Position: [2]float64{.27, .29}}, {Label: "余料记号", Position: [2]float64{.69, .20}}}
		event.Story.Clues = []string{event.Stage.Objects[0].Text, event.Stage.Objects[1].Text}
		event.Story.Dialogue = []DialogueLine{
			{Speaker: "檐下谱", Text: "主梁悬在正殿里。旧木料上留着不同人家的记号。"},
			{Speaker: "社庙", Text: "他们凑不出一根好木头，就把各家的余料抬来。那年春社，屋顶总算没有漏雨。"},
			{Speaker: "拓印师", Text: "我先看看它们怎样接在一起。"},
		}
		event.Story.Outro = "梁重新合拢，旧拼缝仍在。修屋的人没有留下名字，却让檐下多了一处能坐的地方。侧门传来一句：饭凉了，也请进来坐。"
	case "temple_guest":
		event.Puzzle.Type = "echo_guest"
		event.Puzzle.Dependencies = true
		event.Puzzle.Steps = []PuzzleStep{
			{ID: "inspect_bowl", Kind: "observe", Prompt: "看看碗沿留下的磨痕。", Answer: "bowl", Points: 0},
			{ID: "inspect_cape", Kind: "observe", Prompt: "看看门边的旧蓑衣。", Answer: "cape", Points: 0},
			{ID: "guest_place", Kind: "placement", Prompt: "在屋檐下给来客留个位置。", Answer: "bowl", Target: "dry_floor", Requires: []string{"inspect_bowl", "inspect_cape"}, Points: 100},
		}
		event.Stage = &EchoStageSpec{Kind: "guest", Goal: "给檐下的陌生人留一个位置。", Background: "res://assets/landscape/temple_guest.jpeg",
			Objects: []EchoObject{
				{ID: "bowl", Label: "旧碗与筷子", Position: [2]float64{.77, .90}, StepID: "inspect_bowl", Text: "旧碗的边沿磨得发亮，旁边摆着两双筷子。那碗饭被分成了两份。"},
				{ID: "cape", Label: "旧蓑衣", Position: [2]float64{.66, .66}, StepID: "inspect_cape", Text: "蓑衣上的补丁缝得很密，没有留下主人的名字。先让人坐到檐下，再问他从哪里来。"},
			}, DryArea: [][2]float64{{.47, .72}, {.65, .71}, {.80, .87}, {.55, .89}}, BlockedArea: [4]float64{.725, .80, .12, .13}}
		event.Investigations = []InvestigationSpec{{Label: "旧碗与筷子", Position: [2]float64{.77, .90}}, {Label: "旧蓑衣", Position: [2]float64{.66, .66}}}
		event.Story.Clues = []string{event.Stage.Objects[0].Text, event.Stage.Objects[1].Text}
		event.Story.Dialogue = []DialogueLine{
			{Speaker: "檐下谱", Text: "侧厢门边放着半碗冷饭，檐外还在下雨。"},
			{Speaker: "社庙·客声", Text: "那夜我浑身是雨，不敢跨过门槛。他却先把碗推了过来。"},
			{Speaker: "拓印师", Text: "这里还能再坐下一个人。"},
		}
		event.Story.Outro = "你把空碗放进檐下。雨仍落在门外，屋里给后来的人留了位置。前坪传来孩子的数拍声，等着一声鼓响。"
	case "temple_drum":
		event.Puzzle.Type = "echo_drum"
		event.Puzzle.Dependencies = true
		event.Puzzle.Steps = []PuzzleStep{
			{ID: "inspect_drum", Kind: "observe", Prompt: "看看白斑下的鼓纹。", Answer: "drum", Points: 0},
			{ID: "inspect_rope", Kind: "observe", Prompt: "看看鼓槌红绳上的三个结。", Answer: "rope", Points: 0},
			{ID: "drum_reveal", Kind: "skill", Prompt: "用藻井显出旧纹。", Answer: "藻井", Target: "inscription", Requires: []string{"inspect_drum", "inspect_rope"}, Points: 10},
			{ID: "rub_outer", Kind: "rubbing", Prompt: "拓显外环纹。", Answer: "outer", Requires: []string{"drum_reveal"}, Points: 30},
			{ID: "rub_center", Kind: "rubbing", Prompt: "拓显中央纹。", Answer: "center", Requires: []string{"drum_reveal"}, Points: 30},
			{ID: "rub_seam", Kind: "rubbing", Prompt: "拓显旧修补线。", Answer: "seam", Requires: []string{"drum_reveal"}, Points: 30},
		}
		event.Stage = &EchoStageSpec{Kind: "drum", Goal: "让鼓纹与那段数拍重新得到回应。", Background: "res://assets/landscape/temple_drum.jpeg",
			Objects: []EchoObject{
				{ID: "drum", Label: "鼓面旧纹", Position: [2]float64{.48, .47}, StepID: "inspect_drum", Text: "白斑截断了纹样，纹样并没有凭空消失。显出它，不替它画成新样子。"},
				{ID: "rope", Label: "三结红绳", Position: [2]float64{.626, .57}, StepID: "inspect_rope", Text: "鼓槌的旧红绳上留着三个结。孩子每摸一个，就数一拍：一、二、三。鼓声停下之后，那句回应也断在半路。"},
			}, Rubbing: &RubbingSpec{Texture: "res://assets/echo_v1/drum_face.png", BrushRadius: .045, Threshold: .65, Resolution: 56, Regions: []RubbingRegion{
				{ID: "outer", Label: "外环纹", Shape: "ring", Center: [2]float64{.5, .5}, Inner: .32, Outer: .43},
				{ID: "center", Label: "中央纹", Shape: "disk", Center: [2]float64{.5, .5}, Outer: .20},
				{ID: "seam", Label: "旧修补线", Shape: "rect", Rect: [4]float64{.24, .47, .52, .06}},
			}}}
		event.Investigations = []InvestigationSpec{{Label: "鼓面旧纹", Position: [2]float64{.48, .47}}, {Label: "三结红绳", Position: [2]float64{.626, .57}}}
		event.Story.Clues = []string{event.Stage.Objects[0].Text, event.Stage.Objects[1].Text}
		event.Story.Dialogue = []DialogueLine{
			{Speaker: "檐下谱", Text: "前坪的鼓还在，声音却没有接上。"},
			{Speaker: "社庙·童声", Text: "大家说我太小，敲不响鼓。我就在边上数：一、二、三！"},
			{Speaker: "拓印师", Text: "这一次，我来接下一拍。"},
		}
	}
}

func validateEchoStage(event Event) error {
	if !event.Puzzle.Dependencies || event.Stage.Goal == "" {
		return fmt.Errorf("event %s stage needs dependencies and goal", event.ID)
	}
	steps := map[string]PuzzleStep{}
	for _, step := range event.Puzzle.Steps {
		steps[step.ID] = step
	}
	completed := map[string]bool{}
	for len(completed) < len(steps) {
		progress := false
		for id, step := range steps {
			if completed[id] {
				continue
			}
			ready := true
			for _, required := range step.Requires {
				if _, exists := steps[required]; !exists {
					return fmt.Errorf("step %s missing dependency %s", id, required)
				}
				if !completed[required] {
					ready = false
				}
			}
			if ready {
				completed[id] = true
				progress = true
			}
		}
		if !progress {
			return fmt.Errorf("event %s has cyclic step dependencies", event.ID)
		}
	}
	if event.Stage.Kind == "guest" && len(event.Stage.DryArea) < 3 {
		return fmt.Errorf("guest stage needs a dry floor polygon")
	}
	if event.Stage.Kind == "drum" {
		r := event.Stage.Rubbing
		if r == nil || r.Resolution < 16 || r.Resolution > 128 || r.BrushRadius <= 0 || r.BrushRadius > .1 || r.Threshold <= 0 || r.Threshold > 1 || len(r.Regions) != 3 {
			return fmt.Errorf("invalid drum rubbing geometry")
		}
	}
	return nil
}
