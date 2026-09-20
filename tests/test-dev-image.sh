#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import os
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(sys.argv.pop())
PNG = b"\x89PNG\r\n\x1a\n" + b"test image payload"
MOCK = '''#!/usr/bin/env python3
import os
import subprocess
import sys
from pathlib import Path
root = Path(os.environ["IMAGE_TEST_ROOT"])
name = Path(sys.argv[0]).name
if name == "uname":
    print("Darwin")
elif name == "pngpaste":
    if os.environ.get("CAPTURE_FAIL"):
        sys.exit(1)
    Path(sys.argv[1]).write_bytes((root / "source.png").read_bytes())
elif name == "pbcopy":
    if os.environ.get("COPY_FAIL"):
        sys.exit(1)
    (root / "clipboard").write_bytes(sys.stdin.buffer.read())
elif name == "ssh":
    assert sys.argv[1] == "-T", sys.argv
    target = sys.argv[2]
    assert target in ("work-dev", "personal-dev"), sys.argv
    with (root / "ssh.log").open("a") as log:
        log.write(target + "\\n")
    if os.environ.get("SSH_FAIL"):
        sys.exit(255)
    environment = dict(os.environ, HOME=str(root / target))
    if os.environ.get("TRUNCATE_IMAGE"):
        data = sys.stdin.buffer.read()
        sys.exit(subprocess.run(["/bin/sh", "-c", sys.argv[3]], env=environment,
                                input=data[:-1]).returncode)
    sys.exit(subprocess.call(["/bin/sh", "-c", sys.argv[3]], env=environment))
'''


class ImageHelperTests(unittest.TestCase):
    """Exercise real transfer and deletion code with isolated clipboard and SSH adapters."""

    def setUp(self):
        """Create two separate VM homes and a fake Mac clipboard."""
        self.temporary = tempfile.TemporaryDirectory(prefix="dev-image-test.")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        mock_bin = self.root / "bin"
        mock_bin.mkdir()
        for name in ("uname", "pngpaste", "pbcopy", "ssh"):
            script = mock_bin / name
            script.write_text(MOCK)
            script.chmod(0o755)
        for target in ("work-dev", "personal-dev"):
            (self.root / target).mkdir()
        (self.root / "source.png").write_bytes(PNG)
        (self.root / "clipboard").write_text("original clipboard")
        (self.root / "temporary").mkdir()
        self.environment = dict(os.environ, IMAGE_TEST_ROOT=str(self.root),
                                TMPDIR=str(self.root / "temporary"),
                                PATH=str(mock_bin) + os.pathsep + os.environ["PATH"])

    def run_helper(self, *arguments, input="", **environment):
        """Run the CLI without contacting real machines or accessing the clipboard."""
        return subprocess.run([str(ROOT / "bin/dev-image"), *arguments],
                              input=input, text=True, capture_output=True,
                              env=dict(self.environment, **environment))

    def directory(self, target="work-dev"):
        """Return one isolated VM's image directory."""
        return self.root / target / ".local/share/dev-machine/images"

    def send(self, target="work-dev"):
        """Upload the fixture and assert successful publication."""
        result = self.run_helper("send", target)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def test_send_isolation_and_unique_names(self):
        """Preserve image bytes, private permissions and separate VM state."""
        self.send()
        self.send()
        self.send("personal-dev")
        self.assertEqual(len(list(self.directory().iterdir())), 2)
        personal = list(self.directory("personal-dev").iterdir())
        self.assertEqual(len(personal), 1)
        for path in list(self.directory().iterdir()) + personal:
            self.assertEqual(path.read_bytes(), PNG)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertRegex(path.name, r"^dev-image-[0-9a-f]{32}\.png$")
        self.assertEqual(stat.S_IMODE(self.directory().stat().st_mode), 0o700)
        clipboard = (self.root / "clipboard").read_text()
        self.assertIn(str(personal[0]), clipboard)
        self.assertTrue(clipboard.startswith("Inspect this image: "))
        self.assertEqual(list((self.root / "temporary").iterdir()), [])

    def test_failure_preserves_clipboard(self):
        """Do not replace the clipboard after capture, transport or validation failures."""
        for environment in ({"CAPTURE_FAIL": "1"}, {"SSH_FAIL": "1"}, {"TRUNCATE_IMAGE": "1"}):
            result = self.run_helper("send", "work-dev", **environment)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((self.root / "clipboard").read_text(), "original clipboard")
            self.assertEqual(list((self.root / "temporary").iterdir()), [])
        (self.root / "source.png").write_bytes(b"not a PNG")
        result = self.run_helper("send", "work-dev")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.directory().iterdir()), [])
        self.assertEqual((self.root / "clipboard").read_text(), "original clipboard")

    def test_clipboard_failure_keeps_recoverable_path(self):
        """Print the uploaded path when the Mac clipboard cannot be updated."""
        result = self.run_helper("send", "work-dev", COPY_FAIL="1")
        self.assertNotEqual(result.returncode, 0)
        image = next(self.directory().iterdir())
        self.assertIn(str(image), result.stdout)
        self.assertEqual(image.read_bytes(), PNG)

    def test_invalid_arguments_never_connect(self):
        """Reject ambiguous targets, shell input and invalid retention intervals."""
        for arguments in (("send", "work-mini"), ("send", "work-dev;true"),
                          ("clean", "--all"), ("send", "work-dev", "extra"),
                          ("clean", "work-dev", "--older-than", "0d"),
                          ("clean", "work-dev", "--older-than", "-1d"),
                          ("clean", "work-dev", "--older-than", "30"),
                          ("clean", "work-dev", "--older-than", "1d;true")):
            self.assertNotEqual(self.run_helper(*arguments).returncode, 0, arguments)
        self.assertFalse((self.root / "ssh.log").exists())
        self.assertEqual(self.run_helper("--help").returncode, 0)

    def test_clean_requires_matching_confirmation(self):
        """Cancellation, wrong-target confirmation and EOF leave images intact."""
        self.send()
        for answer in ("no\n", "personal-dev\n", ""):
            self.run_helper("clean", "work-dev", input=answer)
            self.assertEqual(len(list(self.directory().iterdir())), 1)

    def test_clean_selects_only_old_owned_images_on_one_vm(self):
        """Keep newer images, other files, symlinks, subdirectories and the other VM."""
        self.send()
        old = next(self.directory().iterdir())
        past = time.time() - 31 * 86400
        os.utime(old, (past, past))
        self.send()
        self.send("personal-dev")
        unrelated = self.directory() / "notes.txt"
        unrelated.write_text("keep")
        link = self.directory() / ("dev-image-" + "a" * 32 + ".png")
        link.symlink_to(old)
        nested = self.directory() / ("dev-image-" + "b" * 32 + ".png")
        nested.mkdir()
        (nested / "keep").write_text("keep")
        result = self.run_helper("clean", "work-dev", "--older-than", "30d", input="work-dev\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Files: 1", result.stdout)
        self.assertIn(f"Size: {len(PNG)} bytes", result.stdout)
        self.assertIn(str(self.directory()), result.stdout)
        self.assertFalse(old.exists())
        self.assertEqual(unrelated.read_text(), "keep")
        self.assertTrue(link.is_symlink())
        self.assertTrue((nested / "keep").exists())
        self.assertEqual(len(list(self.directory("personal-dev").iterdir())), 1)
        result = self.run_helper("clean", "work-dev", input="work-dev\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Deleted 1 images", result.stdout)
        self.assertEqual(len(list(self.directory().iterdir())), 3)

    def test_clean_absent_directory_does_not_create_state(self):
        """Leave an unused VM unchanged when there is nothing to clean."""
        result = self.run_helper("clean", "work-dev")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.root / "work-dev/.local").exists())

    def test_symlinked_directory_and_public_directory_are_rejected(self):
        """Never traverse a replaced image directory or accept a public destination."""
        self.send()
        directory = self.directory()
        preserved = directory.with_name("preserved")
        directory.rename(preserved)
        directory.symlink_to(preserved)
        for command in ("send", "clean"):
            result = self.run_helper(command, "work-dev", input="work-dev\n")
            self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(list(preserved.iterdir())), 1)
        directory.unlink()
        preserved.rename(directory)
        directory.chmod(0o755)
        self.assertNotEqual(self.run_helper("send", "work-dev").returncode, 0)

    def test_changed_files_abort_cleanup_and_new_files_survive(self):
        """Bind confirmation to the previewed files, excluding later uploads."""
        self.send()
        image = next(self.directory().iterdir())
        for change_existing in (True, False):
            with subprocess.Popen([str(ROOT / "bin/dev-image"), "clean", "work-dev"],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True, env=self.environment) as process:
                preview = ""
                while not preview.endswith("to delete these images: "):
                    character = process.stdout.read(1)
                    self.assertTrue(character, preview)
                    preview += character
                if change_existing:
                    image.write_bytes(PNG + b"changed")
                else:
                    self.send()
                _, error = process.communicate("work-dev\n", timeout=10)
                if change_existing:
                    self.assertNotEqual(process.returncode, 0)
                    self.assertIn("changed after preview", error)
                    self.assertTrue(image.exists())
                else:
                    self.assertEqual(process.returncode, 0, error)
                    self.assertFalse(image.exists())
                    self.assertEqual(len(list(self.directory().iterdir())), 1)


unittest.main()
PY
