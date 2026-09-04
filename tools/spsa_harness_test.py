"""Focused qualification tests for Manta's patched Weather Factory bridge."""

from __future__ import annotations

import pathlib
import sys
import unittest
import contextlib
import io
from unittest import mock


WEATHER_FACTORY = pathlib.Path(__file__).parent / "weather-factory"
sys.path.insert(0, str(WEATHER_FACTORY))

import cutechess  # noqa: E402
from cutechess import CutechessMan  # noqa: E402
from spsa import Param, SpsaParams, SpsaTuner  # noqa: E402


class FakeStream:
    def __init__(self, lines: list[str]):
        self.lines = iter([line.encode("ascii") + b"\n" for line in lines] + [b""])

    def readline(self) -> bytes:
        return next(self.lines)


class FakeProcess:
    def __init__(self, lines: list[str], return_code: int = 0):
        self.stdout = FakeStream(lines)
        self.return_code = return_code
        self.killed = False

    def poll(self):
        return self.return_code if self.killed else None

    def kill(self):
        self.killed = True

    def wait(self):
        return self.return_code


def runner(games: int = 2, score_time_losses: bool = False) -> CutechessMan:
    return CutechessMan(
        engine="manta.exe",
        book="book.epd",
        games=games,
        score_time_losses=score_time_losses,
    )


def run_silently(candidate: CutechessMan):
    with contextlib.redirect_stdout(io.StringIO()):
        return candidate.run([], [])


class BridgeTests(unittest.TestCase):
    def test_command_has_margin_and_no_recovery_or_adjudication(self):
        command = runner().get_cutechess_cmd([], [])
        self.assertIn("-each tc=5.0+0.05 timemargin=20", command)
        self.assertNotIn("-recover", command)
        self.assertNotIn("-draw", command)
        self.assertNotIn("-resign", command)

    def test_complete_match_is_accepted(self):
        process = FakeProcess([
            "Score of A vs B: 1 - 0 - 1  [0.750] 2",
            "Finished match",
        ])
        with mock.patch.object(cutechess, "Popen", return_value=process):
            result = run_silently(runner())
        self.assertEqual((result.w, result.l, result.d), (1, 0, 1))

    def test_strict_tune_rejects_time_faults(self):
        for line in (
            "Finished game 1: 0-1 {White loses on time}",
            "Warning; No output from manta",
        ):
            with self.subTest(line=line):
                process = FakeProcess([line])
                with mock.patch.object(cutechess, "Popen", return_value=process):
                    with self.assertRaisesRegex(RuntimeError, "fault"):
                        run_silently(runner())
                self.assertTrue(process.killed)

    def test_clock_tune_scores_completed_time_loss(self):
        process = FakeProcess([
            "Warning; No output from manta",
            "Finished game 1: 0-1 {White loses on time}",
            "Score of A vs B: 0 - 1 - 1  [0.250] 2",
            "Finished match",
        ])
        with mock.patch.object(cutechess, "Popen", return_value=process):
            result = run_silently(runner(score_time_losses=True))
        self.assertEqual((result.w, result.l, result.d), (0, 1, 1))
        self.assertFalse(process.killed)

    def test_infrastructure_faults_remain_strict_for_clock_tune(self):
        for line in (
            "Finished game 1: 1-0 {Black's connection stalls}",
            "Warning; Engine manta is not responsive",
            "Finished game 1: 0-1 {Illegal move}",
            "Failed to set CPU affinity",
        ):
            with self.subTest(line=line):
                process = FakeProcess([line])
                with mock.patch.object(cutechess, "Popen", return_value=process):
                    with self.assertRaisesRegex(RuntimeError, "fault"):
                        run_silently(runner(score_time_losses=True))
                self.assertTrue(process.killed)

    def test_incomplete_or_failed_runner_is_rejected(self):
        cases = (
            FakeProcess(["Score of A vs B: 1 - 0 - 0  [1.000] 1"]),
            FakeProcess([], return_code=7),
        )
        for process in cases:
            with self.subTest(return_code=process.return_code):
                with mock.patch.object(cutechess, "Popen", return_value=process):
                    with self.assertRaises(RuntimeError):
                        run_silently(runner())

    def test_failed_match_cannot_commit_spsa_state(self):
        class FaultingRunner:
            games = 32

            @staticmethod
            def run(_a, _b):
                raise RuntimeError("synthetic match fault")

        parameter = Param("Clock", 1000, 0, 2000, 100)
        tuner = SpsaTuner(
            SpsaParams(a=0.01, c=1.0, A=12),
            [parameter],
            FaultingRunner(),
        )
        with self.assertRaisesRegex(RuntimeError, "synthetic"):
            tuner.step()
        self.assertEqual(tuner.t, 0)
        self.assertEqual(parameter.value, 1000)

    def test_scored_time_loss_commits_spsa_iteration(self):
        class TimeLossRunner:
            games = 32

            @staticmethod
            def run(_a, _b):
                return cutechess.MatchResult(0, 32, 0, -999.0)

        parameter = Param("Clock", 1000, 0, 2000, 100)
        tuner = SpsaTuner(
            SpsaParams(a=0.01, c=1.0, A=12),
            [parameter],
            TimeLossRunner(),
        )
        with contextlib.redirect_stdout(io.StringIO()):
            tuner.step()
        self.assertEqual(tuner.t, 32)


if __name__ == "__main__":
    unittest.main()
