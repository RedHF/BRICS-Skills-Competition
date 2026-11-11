// Regenerate the five authored single-character traces without changing JSON formatting.
const fs = require('node:fs');
const path = require('node:path');

const file = path.join(__dirname, '..', 'LLM-tmp', '服务端', 'content', 'chapters.json');
const catalog = JSON.parse(fs.readFileSync(file, 'utf8'));
const glyphs = {
  bridge_trace: { glyph: '平', prompt: '拓印桥心的“平”字。', strokes: [
    [[.29,.22],[.71,.22]], [[.38,.34],[.43,.45]], [[.63,.34],[.57,.45]],
    [[.25,.52],[.75,.52]], [[.5,.23],[.5,.82]],
  ] },
  guest_trace: { glyph: '安', prompt: '拓印“宁安”中的“安”字。', strokes: [
    [[.5,.13],[.5,.23]], [[.29,.28],[.27,.39]], [[.3,.29],[.73,.29],[.7,.38]],
    [[.46,.43],[.35,.72],[.62,.78]], [[.62,.45],[.44,.8]], [[.27,.59],[.73,.59]],
  ] },
  drum_trace: { glyph: '回', prompt: '拓印鼓面“回春”的“回”字。', strokes: [
    [[.28,.22],[.28,.78]], [[.28,.22],[.72,.22],[.72,.78]],
    [[.4,.39],[.4,.61]], [[.4,.39],[.6,.39],[.6,.61]],
    [[.4,.61],[.6,.61]], [[.28,.78],[.72,.78]],
  ] },
  opera_trace: { glyph: '台', prompt: '拓印戏台的“台”字。', strokes: [
    [[.55,.17],[.35,.43]], [[.35,.43],[.68,.43],[.61,.31]],
    [[.32,.52],[.32,.79]], [[.32,.52],[.69,.52],[.69,.79]], [[.32,.79],[.69,.79]],
  ] },
  tower_trace: { glyph: '心', prompt: '拓印塔心的“心”字。', strokes: [
    [[.27,.53],[.23,.69]], [[.44,.4],[.42,.74],[.47,.82],[.57,.79],[.61,.72]],
    [[.54,.37],[.59,.48]], [[.7,.48],[.77,.63]],
  ] },
};

let changed = 0;
for (const chapter of catalog.chapters) {
  for (const event of chapter.events) {
    for (const step of event.puzzle?.steps ?? []) {
      const authored = glyphs[step.id];
      if (!authored) continue;
      step.prompt = authored.prompt;
      step.trace = {
        glyph: authored.glyph,
        strokes: authored.strokes,
        tolerance: .14,
        aspect_ratio: 1.2,
      };
      changed++;
    }
  }
}
if (changed !== Object.keys(glyphs).length) throw new Error(`Expected 5 traces, found ${changed}`);
fs.writeFileSync(file, JSON.stringify(catalog, null, 2).replace(/\n/g, '\r\n') + '\r\n');
