import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import release_check
from release_check import CheckError

README = "Manta 1.2.2 searches `355,879` nodes on every supported system.\n"
PLAN = "One-thread depth-6 bench is `355,879` nodes.\n"
CHANGELOG = (
    "# Changelog\n\n## [Unreleased]\n\n## [1.2.2] - 2026-11-24\n\n"
    "A patch.\n\n### Highlights\n\n- The point.\n\n### Changed\n\n- A detail.\n\n"
    "## [1.2.1] - 2026-10-08\n\nOlder.\n"
)
NOTES = (
    "A patch.\n\n### Highlights\n\n- The point.\n\n"
    "Every change is in "
    "[CHANGELOG.md](https://github.com/maelic13/manta/blob/v1.2.2/CHANGELOG.md), "
    "which every download also includes.\n"
)


def write_tree(root, version_zig="1.2.2", zon="1.2.2", readme=README, plan=PLAN, changelog=CHANGELOG):
    root = pathlib.Path(root)
    (root / "build_support").mkdir(exist_ok=True)
    (root / "build_support" / "version.zig").write_text(
        f'pub const current = "{version_zig}";\n', encoding="utf-8"
    )
    (root / "build.zig.zon").write_text(
        f'.{{\n    .name = .manta,\n    .version = "{zon}",\n}}\n', encoding="utf-8"
    )
    (root / "README.md").write_text(readme, encoding="utf-8")
    (root / "PLAN.md").write_text(plan, encoding="utf-8")
    (root / "CHANGELOG.md").write_text(changelog, encoding="utf-8")
    for command in (
        ["git", "init", "-q"],
        ["git", "add", "-A"],
        ["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "x"],
    ):
        subprocess.run(command, cwd=root, check=True)
    return root


class ReleaseCheckTests(unittest.TestCase):
    def test_the_page_joins_wrapped_lines(self):
        section = (
            "A summary\nwrapped twice\nhere.\n\n### Highlights\n\n"
            "- **One.** A point\n  that wraps.\n- Two.\n  - A nested\n    item.\n\n"
            "### Changed\n\n- A detail\n  left out.\n"
        )
        page = release_check.release_notes(section, "v1.2.3")
        self.assertTrue(
            page.startswith(
                "A summary wrapped twice here.\n\n### Highlights\n\n"
                "- **One.** A point that wraps.\n- Two.\n  - A nested item.\n\n"
            )
        )
        self.assertNotIn("A detail", page)

    def test_a_release_commit_passes_and_writes_its_notes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = write_tree(temp)
            notes = root / "notes.md"
            message = release_check.check(root, "v1.2.2", "HEAD", notes)
            self.assertIn("bench 6 declared 355879", message)
            self.assertEqual(notes.read_text(encoding="utf-8"), NOTES)

    def test_each_defect_is_refused(self):
        cases = {
            "tag format": (dict(), "1.2.2"),
            "tag names another version": (dict(), "v1.2.3"),
            "sources disagree": (dict(zon="1.2.1"), "v1.2.2"),
            "a -dev version is not a release": (dict(version_zig="1.2.2-dev", zon="1.2.2-dev"), "v1.2.2"),
            "undated section": (dict(changelog=CHANGELOG.replace("] - 2026-11-24", "]")), "v1.2.2"),
            "empty section": (dict(changelog="## [1.2.2] - 2026-11-24\n\n"), "v1.2.2"),
            "no highlights": (
                dict(changelog=CHANGELOG.replace("### Highlights\n\n- The point.\n\n", "")),
                "v1.2.2",
            ),
            "empty highlights": (dict(changelog=CHANGELOG.replace("- The point.\n\n", "")), "v1.2.2"),
            "no summary": (
                dict(changelog=CHANGELOG.replace("A patch.\n\n### Highlights", "### Highlights")),
                "v1.2.2",
            ),
            "fingerprint mismatch": (
                dict(plan="One-thread depth-6 bench is `123,456` nodes.\n"),
                "v1.2.2",
            ),
        }
        for label, (tree, tag) in cases.items():
            with self.subTest(label), tempfile.TemporaryDirectory() as temp:
                root = write_tree(temp, **tree)
                with self.assertRaises(CheckError):
                    release_check.check(root, tag, "HEAD", None)

    def test_head_off_the_base_is_refused(self):
        with tempfile.TemporaryDirectory() as temp:
            root = write_tree(temp)
            subprocess.run(["git", "branch", "base"], cwd=root, check=True)
            (root / "extra.txt").write_text("x\n", encoding="utf-8")
            subprocess.run(["git", "add", "-A"], cwd=root, check=True)
            subprocess.run(
                ["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "y"],
                cwd=root,
                check=True,
            )
            with self.assertRaises(CheckError):
                release_check.check(root, "v1.2.2", "base", None)

    def test_a_patch_line_from_the_minor_release_is_accepted(self):
        def commit(root, name):
            (root / name).write_text("x\n", encoding="utf-8")
            subprocess.run(["git", "add", "-A"], cwd=root, check=True)
            subprocess.run(
                ["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", name],
                cwd=root,
                check=True,
            )

        with tempfile.TemporaryDirectory() as temp:
            root = write_tree(temp)
            subprocess.run(["git", "tag", "v1.2.0"], cwd=root, check=True)
            subprocess.run(["git", "branch", "base"], cwd=root, check=True)
            subprocess.run(["git", "checkout", "-q", "base"], cwd=root, check=True)
            commit(root, "later-work.txt")
            subprocess.run(["git", "checkout", "-q", "-b", "patch", "v1.2.0"], cwd=root, check=True)
            commit(root, "fix.txt")
            self.assertIn(
                "patch line from v1.2.0",
                release_check.check(root, "v1.2.2", "base", None),
            )
            with self.assertRaises(CheckError):
                release_check.ensure_on_line(root, "1.3.0", "base")

    def test_version_reads_dev_and_refuses_mismatch(self):
        with tempfile.TemporaryDirectory() as temp:
            self.assertEqual(
                release_check.engine_version(write_tree(temp, version_zig="1.2.3-dev", zon="1.2.3-dev")),
                "1.2.3-dev",
            )
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaises(CheckError):
                release_check.engine_version(write_tree(temp, version_zig="1.2.3-dev", zon="1.2.2"))


if __name__ == "__main__":
    unittest.main()
