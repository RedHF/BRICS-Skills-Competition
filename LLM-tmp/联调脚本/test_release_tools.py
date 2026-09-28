"""发行工具纯逻辑的单元测试。

跑法： python -m unittest discover -s "LLM-tmp/联调脚本" -p "test_release_tools.py" -v

临时目录建在系统临时目录下，但**用普通 `mkdir` 而不是 `tempfile.mkdtemp`**：本机沙箱下，
`mkdtemp` 在 Windows 上建的目录带私有 ACL，子进程写不进去（WinError 5），连删都删不掉。
普通 `mkdir` 继承父目录的 ACL，写入和清理都正常。
"""
import hashlib
import itertools
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import package_release as pr

_TEMP_COUNTER = itertools.count()


class FolderTestCase(unittest.TestCase):
    """给需要真实目录的用例一个建得起来、也写得进去、也删得掉的临时目录。"""

    def temp_folder(self) -> Path:
        folder = Path(tempfile.gettempdir()) / f'yanxia-release-tools-{os.getpid()}-{next(_TEMP_COUNTER):04d}'
        folder.mkdir(parents=True, exist_ok=True)
        self.addCleanup(shutil.rmtree, folder, ignore_errors=True)
        return folder


class ReleaseNamesTest(unittest.TestCase):
    """版本名 → 发行目录名、ZIP 名、校验文件名的映射。"""

    def test_defaults_keep_the_original_v10_target(self):
        names = pr.release_names()
        self.assertEqual(names['stem'], '檐下千秋-v10-Windows-x64-20260914')
        self.assertEqual(names['folder'], '檐下千秋-v10-Windows-x64-20260914')
        self.assertEqual(names['zip'], '檐下千秋-v10-Windows-x64-20260914.zip')
        self.assertEqual(names['checksum'], '檐下千秋-v10-Windows-x64-20260914.zip.sha256')

    def test_existing_v10_package_name_is_reproducible(self):
        names = pr.release_names('v10', '可玩性修复版', '20260915')
        self.assertEqual(names['zip'], '檐下千秋-v10-可玩性修复版-20260915.zip')
        self.assertEqual(names['checksum'], '檐下千秋-v10-可玩性修复版-20260915.zip.sha256')

    def test_v11_names(self):
        names = pr.release_names('v11', '横屏水墨版', '20260928')
        self.assertEqual(names['stem'], '檐下千秋-v11-横屏水墨版-20260928')
        self.assertEqual(names['folder'], '檐下千秋-v11-横屏水墨版-20260928')
        self.assertEqual(names['checksum'], '檐下千秋-v11-横屏水墨版-20260928.zip.sha256')

    def test_defaults_are_the_module_constants(self):
        self.assertEqual(pr.DEFAULT_VERSION, 'v10')
        self.assertEqual(pr.DEFAULT_EDITION, 'Windows-x64')
        self.assertEqual(pr.DEFAULT_DATE, '20260914')


class ManifestTest(FolderTestCase):
    """SHA256.txt 的行格式与清单内容。"""

    def test_line_format_uses_two_spaces(self):
        self.assertEqual(pr.manifest_line('abc', 'a/b.txt'), 'abc  a/b.txt')

    def test_line_round_trip(self):
        digest, relative = pr.parse_manifest_line(
            pr.manifest_line('abc', 'server/content/chapters.json'))
        self.assertEqual((digest, relative), ('abc', 'server/content/chapters.json'))

    def test_sha256_bytes_matches_hashlib(self):
        self.assertEqual(pr.sha256_bytes(b'yanxia'), hashlib.sha256(b'yanxia').hexdigest())

    def test_build_manifest_is_sorted_and_skips_the_manifest_itself(self):
        folder = self.temp_folder()
        (folder / 'b.txt').write_text('b', encoding='utf-8')
        (folder / 'a.txt').write_text('a', encoding='utf-8')
        (folder / pr.MANIFEST_FILE).write_text('self', encoding='utf-8')
        entries = pr.build_manifest(folder)
        self.assertEqual([entry['path'] for entry in entries], ['a.txt', 'b.txt'])
        self.assertEqual(entries[1], {
            'path': 'b.txt',
            'bytes': 1,
            'sha256': hashlib.sha256(b'b').hexdigest(),
        })


class ReleaseLayoutTest(FolderTestCase):
    """发行目录「必须有且只有这 8 项」这条 DoD 的可执行版本。"""

    def fill(self, folder: Path) -> None:
        for name in pr.expected_entries():
            target = folder / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('x', encoding='utf-8')

    def test_expected_entries_are_exactly_eight(self):
        entries = pr.expected_entries()
        self.assertEqual(len(entries), 8)
        self.assertEqual(sorted(entries), list(entries))
        self.assertIn('檐下千秋.exe', entries)
        self.assertIn('server/yanxia-server.exe', entries)
        self.assertIn('server/content/chapters.json', entries)
        self.assertIn(pr.MANIFEST_FILE, entries)

    def test_complete_folder_has_no_findings(self):
        folder = self.temp_folder()
        self.fill(folder)
        self.assertEqual(pr.audit_release(folder),
                         {'missing': [], 'forbidden': [], 'extra': []})

    def test_audit_reports_forbidden_test_artifacts(self):
        folder = self.temp_folder()
        self.fill(folder)
        (folder / 'save.json').write_text('{}', encoding='utf-8')
        (folder / 'settings.cfg').write_text('x', encoding='utf-8')
        (folder / 'tests').mkdir()
        (folder / 'tests' / 'release_smoke.gd').write_text('x', encoding='utf-8')
        report = pr.audit_release(folder)
        self.assertEqual(report['missing'], [])
        self.assertEqual(report['forbidden'],
                         ['save.json', 'settings.cfg', 'tests/release_smoke.gd'])
        self.assertEqual(report['extra'], [])

    def test_audit_reports_missing_required_files(self):
        folder = self.temp_folder()
        (folder / '檐下千秋.exe').write_text('x', encoding='utf-8')
        report = pr.audit_release(folder)
        self.assertIn('server/yanxia-server.exe', report['missing'])
        self.assertIn(pr.MANIFEST_FILE, report['missing'])
        self.assertEqual(report['forbidden'], [])

    def test_audit_reports_unknown_file_as_extra(self):
        folder = self.temp_folder()
        self.fill(folder)
        (folder / '更新与素材记录.md').write_text('x', encoding='utf-8')
        self.assertEqual(pr.audit_release(folder)['extra'], ['更新与素材记录.md'])


if __name__ == '__main__':
    unittest.main()
