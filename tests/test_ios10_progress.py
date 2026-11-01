"""Progress must reflect measured work and never turn a failure into success."""
import contextlib
import io
from pathlib import Path
import plistlib
import struct
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "resources/ios10"))
from macho import ImageError
from prepare import Runner, copy_stream, digest, rewrite_zip
from progress import Progress, DmgProgress, dmg_extract_size, stream_tool


class ProgressTests(unittest.TestCase):
    def test_byte_counts_are_monotonic_and_success_is_explicit(self):
        output = io.StringIO()
        with Progress("Copying", 8, stream=output) as progress:
            target = io.BytesIO()
            copy_stream(io.BytesIO(b"abcd"), target, progress)
            self.assertEqual(target.getvalue(), b"abcd")
            self.assertEqual(progress.done, 4)
            progress.update(2)
            self.assertEqual(progress.done, 4)
            progress.update(8)
            self.assertNotIn("100.0%", output.getvalue())
        self.assertIn("50.0%", output.getvalue())
        self.assertIn("100.0%  done", output.getvalue())
        self.assertNotIn("\r", output.getvalue())

    def test_failure_never_displays_full_completion(self):
        output = io.StringIO()
        with self.assertRaises(RuntimeError):
            with Progress("Checking", 4, "steps", stream=output) as progress:
                progress.advance(4)
                raise RuntimeError("verification failed")
        self.assertNotIn("100.0%", output.getvalue())
        self.assertIn("stopped", output.getvalue())
        self.assertIn("steps", output.getvalue())

    def test_dmg_compression_ignores_partition_map_and_uses_remaining_sectors(self):
        progress = Progress("Compressing", 100 * 512, stream=io.StringIO())
        parser = DmgProgress(progress, "build")
        parser("run 0: sectors=1, left=1")
        self.assertEqual(progress.done, 0)
        parser("Writing main data blkx...")
        parser("run 100: sectors=10, left=75")
        self.assertEqual(progress.done, 25 * 512)
        parser("run 110: skipping sectors=20, left=60")
        self.assertEqual(progress.done, 40 * 512)
        parser("Inserting main blkx...")
        self.assertEqual(progress.done, 100 * 512)
        parser("run 0: sectors=8, left=8")
        self.assertEqual(progress.done, 100 * 512)

    def test_dmg_extraction_counts_only_completed_runs(self):
        progress = Progress("Extracting", 10000, stream=io.StringIO())
        parser = DmgProgress(progress, "extract")
        parser("run 100: start=2048 sectors=2, length=100, fileOffset=0x80")
        self.assertEqual(progress.done, 2048)
        parser("unrelated tool diagnostic")
        self.assertEqual(progress.done, 2048)

    def test_udif_size_uses_hfs_partition_and_bounds_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "fixture.dmg"
            data = b"mish" + b"\0" * 12 + struct.pack(">Q", 1234)
            xml = plistlib.dumps({"resource-fork": {"blkx": [
                {"Name": "Apple_partition_map", "Data": b"map"},
                {"Name": "disk image (Apple_HFSX : 5)", "Data": data}]}})
            trailer = bytearray(512)
            trailer[:4] = b"koly"
            struct.pack_into(">QQ", trailer, 216, 16, len(xml))
            p.write_bytes(b"\0" * 16 + xml + trailer)
            self.assertEqual(dmg_extract_size(p), 1234 * 512)
            struct.pack_into(">Q", trailer, 224, 17 * 1024**2)
            p.write_bytes(b"\0" * 16 + xml + trailer)
            self.assertIsNone(dmg_extract_size(p))
            malformed = b'<?xml version="1.0"?><plist><broken'
            struct.pack_into(">Q", trailer, 224, len(malformed))
            p.write_bytes(b"\0" * 16 + malformed + trailer)
            self.assertIsNone(dmg_extract_size(p))

    def test_tool_output_is_received_before_exit_and_failure_is_logged(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            marker = p / "seen"
            code = """import os,sys,time
from pathlib import Path
assert os.isatty(1)
print('run 100: start=2048 sectors=2, length=100, fileOffset=0x80', flush=True)
deadline=time.monotonic()+3
while not Path(sys.argv[1]).exists() and time.monotonic()<deadline: time.sleep(0.01)
print('stream received' if Path(sys.argv[1]).exists() else 'buffered until exit', flush=True)
sys.exit(23)
"""
            lines = []
            def receive(line):
                lines.append(line)
                marker.write_text('received')
            # Runner must preserve the nonzero status and diagnostics even
            # while progress callbacks receive output through the private PTY.
            runner = Runner(Path(sys.executable).parent, p / "tools.log")
            with self.assertRaises(ImageError):
                runner.run(Path(sys.executable).name, "-c", code, str(marker), on_line=receive)
            self.assertIn("stream received", lines)
            self.assertNotIn("buffered until exit", lines)
            self.assertIn('"exit_code": 23', (p / "tools.log").read_text())

    def test_checksum_progress_preserves_digest_and_reads_all_bytes(self):
        import hashlib
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "input"
            p.write_bytes(b"contents" * 200000)
            with Progress("Hashing", p.stat().st_size, stream=io.StringIO()) as progress:
                self.assertEqual(digest(p, progress=progress), hashlib.sha256(p.read_bytes()).hexdigest())
                self.assertEqual(progress.done, p.stat().st_size)

    def test_corrupt_zip_still_fails_without_publishing_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp)
            source, output = p / "source.zip", p / "output.zip"
            with zipfile.ZipFile(source, "w") as z:
                z.writestr("component", b"unique contents")
            raw = source.read_bytes().replace(b"unique contents", b"broken contents")
            source.write_bytes(raw)
            display = io.StringIO()
            with contextlib.redirect_stdout(display), self.assertRaises(zipfile.BadZipFile):
                rewrite_zip(source, output, {})
            self.assertFalse(output.exists())
            self.assertIn("stopped", display.getvalue())
            self.assertNotIn("100.0%", display.getvalue())


if __name__ == "__main__":
    unittest.main()
