"""Copy the supplied recordings and build deterministic cue/text indexes (no synthesis)."""
from pathlib import Path
import json
import shutil
import wave

ROOT = Path(__file__).resolve().parents[2]
source = ROOT / 'Art_Material/Generation/生成音频'
target = ROOT / 'LLM-tmp/客户端/assets/voice'
target.mkdir(parents=True, exist_ok=True)
catalog = json.loads((ROOT / 'LLM-tmp/服务端/content/chapters.json').read_text(encoding='utf-8-sig'))
cues, lines, used, missing = {}, {}, set(), []
for recording in sorted(source.rglob('*.wav')):
    assert recording.stem not in cues, f'Duplicate cue: {recording.name}'
    with wave.open(str(recording)) as audio:
        assert audio.getnframes() > 0 and audio.getcomptype() == 'NONE'
    shutil.copy2(recording, target / recording.name)
    cues[recording.stem] = 'res://assets/voice/' + recording.name

def bind(key, text):
    if key not in cues:
        missing.append({'cue':key, 'text':text})
        return
    used.add(key)
    lines[text] = key
    if '：' in text:
        lines[text.split('：', 1)[1]] = key

for chapter in catalog['chapters']:
    for event in chapter['events']:
        eid, story = event['id'], event['story']
        for field, suffix in [('dialogue', 'dialogue'), ('beats', 'beat'), ('clues', 'clue')]:
            for i, line in enumerate(story[field], 1):
                bind(f'{eid}_{suffix}_{i:02}', line['text'] if isinstance(line, dict) else line)
        for field, suffix in [('outro','outro'), ('keep_response','keep'), ('forget_response','forget'), ('before_battle','before_battle'), ('chapter_outro','chapter_outro'), ('first_clear_whisper','first_clear')]:
            if story.get(field): bind(f'{eid}_{suffix}', story[field])
for i, line in enumerate(catalog['failure_scene']['dialogue'], 1):
    bind(f'failure_line_{i:02}', line['text'])
for reason, line in catalog['failure_scene']['first_lines'].items():
    bind('failure_first_' + reason, line['text'])
for mid, memory in catalog['memories'].items():
    assert mid in cues, f'Missing collectible echo: {mid}'
    used.add(mid)
    memory['echo_audio'] = cues[mid]
assert used == set(cues), f'Unmapped recordings: {set(cues)-used}'
(ROOT / 'LLM-tmp/服务端/content/chapters.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
(target / 'index.json').write_text(json.dumps({'cues':cues,'lines':lines,'missing':missing}, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print(f'Imported and mapped {len(cues)} recordings.')
print(f'Text-only lines without supplied audio: {missing}')
