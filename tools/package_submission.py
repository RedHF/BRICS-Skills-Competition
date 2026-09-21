"""Rebuild the local competition ZIP and integrity manifests (Python stdlib only)."""
from pathlib import Path
from datetime import date
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'output/参赛材料/本科组_Track1_第二队'


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def save_json(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    # The ignored executable must exist locally before creating a submission ZIP.
    runtime = PACKAGE / 'Task03/Final/Track01_Task03_第二队_檐下千秋_核心可玩实体/Windows-x64'
    for name in ['檐下千秋.exe', 'server/yanxia-server.exe']:
        if not (runtime / name).is_file():
            raise SystemExit('Restore the complete runtime from dist first: ' + name)
    excluded_names = {'Thumbs.db', '.DS_Store'}
    leftover = [p for p in PACKAGE.rglob('*') if p.is_file() and (p.name in excluded_names or p.name.startswith('~$'))]
    if leftover:
        raise SystemExit('Remove temporary files before packaging: ' + repr(leftover))
    checks_path = PACKAGE / '提交核验结果.json'
    checks = json.loads(checks_path.read_text(encoding='utf-8'))
    checks['final_package_date'] = date.today().isoformat()
    checks['temporary_file_cleanup'] = {'thumbnail_cache_files': 0, 'documents_and_assets_unchanged': True}
    save_json(checks_path, checks)
    manifest_path = PACKAGE / '文件清单.json'
    sha_path = PACKAGE / 'SHA256.txt'
    files = sorted(p for p in PACKAGE.rglob('*') if p.is_file() and p not in {manifest_path, sha_path})
    manifest = [{'path': p.relative_to(PACKAGE).as_posix(), 'bytes': p.stat().st_size, 'sha256': sha256(p)} for p in files]
    save_json(manifest_path, {'date': date.today().isoformat(), 'scope': '全部交付文件，不包括本清单和SHA256.txt自身', 'files': manifest})
    sha_path.write_text(''.join(f'{entry["sha256"]}  {entry["path"]}\n' for entry in manifest), encoding='utf-8')
    archive = PACKAGE.with_suffix('.zip')
    pending = archive.with_name(archive.name + '.part')
    print(f'Packaging {len(files) + 2} files...', flush=True)
    with zipfile.ZipFile(pending, 'w', zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as output:
        for path in files + [manifest_path, sha_path]:
            output.write(path, path.relative_to(PACKAGE.parent).as_posix())
    print('Checking archive CRC and every manifest hash...', flush=True)
    with zipfile.ZipFile(pending) as output:
        if output.testzip() is not None:
            raise RuntimeError('Archive CRC check failed')
        for entry in manifest:
            data = output.read(PACKAGE.name + '/' + entry['path'])
            if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
                raise RuntimeError('Archive content differs: ' + entry['path'])
    pending.replace(archive)
    result = {'archive': str(archive), 'bytes': archive.stat().st_size, 'sha256': sha256(archive), 'files': len(files) + 2, 'crc': 'PASS', 'all_manifest_hashes': 'PASS', 'date': date.today().isoformat()}
    archive.with_suffix('.zip.sha256').write_text(result['sha256'] + '  ' + archive.name + '\n', encoding='utf-8')
    save_json(PACKAGE.parent / '压缩包核验结果.json', result)
    print(json.dumps(result, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
