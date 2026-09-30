"""Export project-visible Codex records with provenance, redaction and JSONL validation."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
from collections import defaultdict
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'output/参赛材料/本科组_Track1_第二队'
DEST = PACKAGE / 'Task03/Original/AI协作记录/本机会话导出'
CODEX = Path.home() / '.codex'
ALLOWED_TOOLS = {'custom_tool_call', 'custom_tool_call_output', 'function_call', 'function_call_output'}
SECRET = re.compile(r'\b(?:sk-[A-Za-z0-9._-]{10,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})')
INJECTED = ('<environment_context>', '<recommended_plugins>', '<external_codex_apps_open_page>',
            '<permissions instructions>', '<skills_instructions>', '<codex_apps_client_time_context>')

def digest(data):
    return hashlib.sha256(data).hexdigest()

def atomic_text(path, value):
    temporary = path.with_name('export-writing.tmp')
    temporary.write_text(value, encoding='utf-8', newline='\n')
    temporary.replace(path)

def clean_text(value):
    value = value.replace('\r\n', '\n').replace('\r', '\n')
    value = SECRET.sub('[REDACTED_CREDENTIAL]', value)
    value = re.sub(r'(?i)(Bearer\s+)[A-Za-z0-9._~+/-]{12,}', r'\1[REDACTED_CREDENTIAL]', value)
    value = re.sub(r'(?i)((?:api[_-]?key|access[_-]?token|authorization)\s*[=:]\s*[\"\x27]?)(?!\[REDACTED)([A-Za-z0-9._~-]{20,})', r'\1[REDACTED_CREDENTIAL]', value)
    for path, replacement in ((str(ROOT), '<PROJECT_ROOT>'), (str(CODEX), '<CODEX_HOME>'), (str(Path.home()), '<USER_HOME>')):
        for spelling in (path, path.replace('\\', '/'), path.replace('\\', '\\\\')):
            value = re.sub(re.escape(spelling), replacement, value, flags=re.I)
    value = re.sub(r'data:(?:image|audio|video)/[^\s\"\x27]+', '[MEDIA_DATA_OMITTED]', value)
    value = re.sub(r'[A-Za-z0-9+/]{2048,}={0,2}', '[BINARY_DATA_OMITTED]', value)
    return value

def sanitize(value):
    if isinstance(value, str):
        return clean_text(value)
    if isinstance(value, list):
        return [sanitize(x) for x in value]
    if isinstance(value, dict):
        return {k: ('[MEDIA_DATA_OMITTED]' if k in {'data', 'encrypted_content', 'image_url', 'audio_url'} else sanitize(v)) for k, v in value.items()}
    return value

def message_text(payload):
    content = payload.get('content', [])
    if isinstance(content, str):
        return content
    return '\n'.join(x.get('text', '[附件或非文本内容]') for x in content if isinstance(x, dict))

def read_source(path):
    # Read one stable byte snapshot, including the currently active conversation.
    data = path.read_bytes()
    records = []; meta = {}
    for line in data.splitlines():
        try:
            r = json.loads(line)
        except json.JSONDecodeError:
            continue  # A live source may end with one incomplete write.
        if r.get('type') == 'session_meta' and not meta:
            meta = r.get('payload', {})
        elif r.get('type') == 'response_item':
            records.append(r)
    return data, meta, records

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    index_path = DEST / '导出索引.json'
    old = json.loads(index_path.read_text(encoding='utf-8'))
    groups = defaultdict(list); excluded = []
    for folder in ('sessions', 'archived_sessions'):
        for source in sorted((CODEX / folder).rglob('*.jsonl')):
            # Inspect metadata first so unrelated records never enter the export.
            with source.open(encoding='utf-8') as stream:
                try:
                    first = json.loads(stream.readline())
                except json.JSONDecodeError:
                    continue
            if first.get('type') != 'session_meta' or 'BRICS-Skills-Competition' not in str(first.get('payload', {}).get('cwd', '')):
                continue
            data, meta, records = read_source(source)
            source_name = '<CODEX_HOME>/' + source.relative_to(CODEX).as_posix()
            if meta.get('thread_source') == 'guardian_review' or any('The following is the Codex agent history whose request action you are assessing' in message_text(r['payload']) for r in records if r['payload'].get('type') == 'message' and r['payload'].get('role') == 'user'):
                excluded.append({'source': source_name, 'reason': '审批审计会话'})
                continue
            visible = []
            for r in records:
                q = r['payload']; typ = q.get('type')
                if typ == 'message':
                    if q.get('role') not in {'user', 'assistant'} or q.get('channel') in {'analysis', 'summary'} or q.get('phase') in {'analysis', 'summary'}:
                        continue
                    text = message_text(q).strip()
                    if not text or (q.get('role') == 'user' and text.startswith(INJECTED)):
                        continue
                    record = {'timestamp': r.get('timestamp'), 'type': 'message', 'role': q['role'], 'text': clean_text(text)}
                    if q.get('phase'):
                        record['phase'] = q['phase']
                elif typ in ALLOWED_TOOLS:
                    allowed = ('name', 'call_id', 'arguments', 'input', 'output')
                    record = {'timestamp': r.get('timestamp'), 'type': typ, **{k: sanitize(q[k]) for k in allowed if k in q}}
                    for k in ('output',):
                        full = record.get(k)
                        if full is not None and not isinstance(full, str):
                            full = json.dumps(full, ensure_ascii=False)
                        if isinstance(full, str) and len(full) > 40000:
                            record[k] = full[:40000] + '\n[工具输出过长，展示截断；完整脱敏输出哈希见本条记录]'
                            record['full_redacted_output_sha256'] = digest(full.encode())
                            record['full_redacted_output_characters'] = len(full)
                else:
                    continue
                record['source_file'] = source.name
                record['_event_id'] = q.get('id') or q.get('call_id')
                visible.append(record)
            if not visible:
                excluded.append({'source': source_name, 'reason': '无用户可见对话或工具记录'})
                continue
            groups[meta['id']].append((meta, visible, {'source': source_name, 'source_sha256': digest(data), 'bytes': len(data)}))
    entries = []
    (DEST / 'Codex').mkdir(exist_ok=True)
    for sid, fragments in sorted(groups.items()):
        events = {}; sources = []
        for meta, records, provenance in fragments:
            sources.append(provenance)
            for r in records:
                event_id = r.pop('_event_id', None)
                key = (r['type'], r.get('role'), event_id) if event_id else (r['type'], r.get('role'), r['timestamp'], digest(json.dumps({k:v for k,v in r.items() if k!='source_file'}, sort_keys=True, ensure_ascii=False).encode()))
                events[key] = r
        records = sorted(events.values(), key=lambda r:r.get('timestamp') or '')
        users = [r['text'] for r in records if r['type']=='message' and r['role']=='user']
        title = next((x for x in users if not x.startswith('<')), users[0] if users else '项目开发子任务')
        if 'My request:' in title:
            title = title.split('My request:', 1)[1].strip()
        title = title[:120].replace('\n', ' ')
        meta = fragments[-1][0]
        export_meta = {'type':'export_metadata', 'session_id':sid, 'workspace':'<PROJECT_ROOT>', 'export_time':datetime.now(timezone(timedelta(hours=8))).isoformat(timespec='seconds'), 'sources':sources, 'scope':'用户和助手可见消息及工具调用结果；不包含系统指令、内部推理、审批审计、二进制媒体；工具输出超过40000字符时截断并保留脱敏内容哈希'}
        jsonl_path = DEST / 'Codex' / (sid + '.jsonl')
        atomic_text(jsonl_path, '\n'.join(json.dumps(r,ensure_ascii=False) for r in [export_meta]+records)+'\n')
        md = [f'# Codex 项目 AI 协作记录\n\n会话 ID：{sid}\n\n导出时间：{export_meta["export_time"]}\n\n工作区：<PROJECT_ROOT>\n\n标题：{title}\n\n{export_meta["scope"]}\n\n来源片段：{len(sources)} 个，原文件哈希见导出索引。当前会话为导出时快照，后续消息不包含在本次快照内。\n']
        for i, r in enumerate(records, 1):
            label = r.get('role') or r.get('name') or r['type']
            md.append(f'\n## {i} {label} {r.get("timestamp", "")}\n\n')
            if r['type']=='message':
                md.append(r['text']+'\n')
            else:
                md.append('````json\n'+json.dumps({k:v for k,v in r.items() if k not in {'timestamp','source_file'}},ensure_ascii=False,indent=2)+'\n````\n')
        md_path = jsonl_path.with_suffix('.md')
        readable=''.join(md)
        readable='\n'.join(line.rstrip() for line in readable.splitlines())+'\n'
        atomic_text(md_path, readable)
        entries.append({'platform':'Codex', 'id':sid, 'title':title, 'sources':sources, 'export_sha256':digest(jsonl_path.read_bytes()), 'readable_md_sha256':digest(md_path.read_bytes()), 'messages':sum(r['type']=='message' for r in records), 'records':len(records)+1, 'path':md_path.relative_to(PACKAGE).as_posix(), 'origin':meta.get('thread_source','user'), 'bytes':jsonl_path.stat().st_size})
    other = [sanitize(x) for x in old['sessions'] if x['platform'] != 'Codex']
    current = {'export_date':'2026-09-30', 'workspace':'<PROJECT_ROOT>', 'scope':'本机 sessions 与 archived_sessions 中工作区匹配本项目的主会话和开发子任务；同一会话片段合并、重复事件去重；保留原有 DeepSeek 导出', 'sessions':entries+other, 'excluded':excluded}
    atomic_text(index_path, json.dumps(current,ensure_ascii=False,indent=2)+'\n')
    # Validate delivered JSONL and every index hash, without printing contents.
    total_records=0; total_messages=0
    for e in current['sessions']:
        md_path = PACKAGE/e['path']; jp=md_path.with_suffix('.jsonl')
        assert digest(md_path.read_bytes()) == e['readable_md_sha256'], md_path
        assert digest(jp.read_bytes()) == e['export_sha256'], jp
        for line in jp.read_text(encoding='utf-8').splitlines():
            json.loads(line); total_records+=1
        total_messages+=e['messages']
        assert not SECRET.search(md_path.read_text(encoding='utf-8')), md_path
        assert not SECRET.search(jp.read_text(encoding='utf-8')), jp
    result={'Codex':len(entries), 'DeepSeek_Harness':len(other), 'visible_messages':total_messages, 'secrets_redacted':True, 'jsonl_records_validated':total_records, 'final_hashes_verified':True, 'date':'2026-09-30', 'source_fragments':sum(len(e['sources']) for e in entries), 'excluded_sources':len(excluded)}
    checks_path=PACKAGE/'提交核验结果.json'; checks=json.loads(checks_path.read_text(encoding='utf-8')); checks['ai_export']=result
    atomic_text(checks_path, json.dumps(checks,ensure_ascii=False,indent=2)+'\n')
    overview=['# 本项目 AI 留痕导出目录\n\n导出日期：2026年9月30日（北京时间）。\n\n本次整理25个Codex会话，合并37个源日志片段，并保留5个DeepSeek harness会话。仅记录用户及助手的可见消息和工具操作；来源原文件、导出文件和可读版哈希见[导出索引](导出索引.json)。当前整理会话为导出时快照。\n\n密钥与个人路径已脱敏。内部推理、系统指令、审批审计和空会话不进入记录；二进制媒体只保留附件说明。长工具输出超过40000字符时截断，记录中保留完整脱敏文本的哈希和字符数。\n\n| 平台 | 会话及可读记录 | 可见消息 | JSONL记录 |\n| --- | --- | ---: | ---: |\n']
    for e in current['sessions']:
        rel=Path(e['path']).relative_to(DEST.relative_to(PACKAGE)).as_posix()
        overview.append(f'| {e["platform"]} | [{e["id"]}]({rel}) | {e["messages"]} | {e["records"]} |\n')
    overview.append(f'\n合计可见消息{total_messages}条，已验证JSONL记录{total_records}条。未导出的本项目日志共{len(excluded)}个（审批审计或无可见内容），原因逐项列于索引。\n')
    atomic_text(DEST/'导出目录.md', ''.join(overview).replace('合并37个源日志片段', f'合并{result["source_fragments"]}个源日志片段'))
    print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':
    main()
