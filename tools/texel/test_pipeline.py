#!/usr/bin/env python3
"""Focused invariants for ADR-0056 sampling and grouped extraction."""

import random
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import chess
import chess.pgn

import extract
import extract_parallel
import fit
import fit_man_e20
import sample_fens


class PipelineTests(unittest.TestCase):
    def test_phase_targets_are_exact(self):
        self.assertEqual(sample_fens.bucket_targets(12), [3, 3, 2, 2, 2])
        self.assertEqual(extract.allocate(12, [1, 1, 1, 1, 1]), [3, 3, 2, 2, 2])

    def test_phase_boundaries_cover_zero_through_twenty_four(self):
        expected = {24: 0, 20: 0, 19: 1, 14: 1, 13: 2,
                    8: 2, 7: 3, 3: 3, 2: 4, 0: 4}
        for phase, bucket in expected.items():
            self.assertEqual(extract.phase_bucket(phase), bucket)

    def test_static_identity_keeps_rule_fifty_clock(self):
        first = "8/8/8/8/8/8/P6p/4K2k w - - 17 42"
        second = "8/8/8/8/8/8/P6p/4K2k w - - 18 42"
        third = "8/8/8/8/8/8/P6p/4K2k w - - 17 99"
        self.assertNotEqual(extract.fen_key(first), extract.fen_key(second))
        self.assertEqual(extract.fen_key(first), extract.fen_key(third))

    def test_reservoir_is_bounded_and_reproducible(self):
        def draw():
            reservoir = extract.Reservoir(25, random.Random(42))
            for value in range(1_000):
                reservoir.offer((str(value), 0.5, 0))
            return reservoir.items
        self.assertEqual(draw(), draw())
        self.assertEqual(len(draw()), 25)

    def test_whole_start_determines_split(self):
        game = chess.pgn.Game()
        game.headers["Result"] = "1/2-1/2"
        game.add_variation(chess.Move.from_uci("e2e4"))
        clone = chess.pgn.Game()
        clone.headers["Result"] = "1-0"
        clone.add_variation(chess.Move.from_uci("d2d4"))
        self.assertEqual(extract.start_digest(game), extract.start_digest(clone))
        self.assertEqual(extract.split_for(game, 5, 5), extract.split_for(clone, 5, 5))

    def test_start_position_can_supply_one_bounded_row(self):
        game = chess.pgn.Game()
        game.headers["Result"] = "1/2-1/2"
        game.add_variation(chess.Move.from_uci("e2e4"))
        rows, rejected = extract.process_game(game, 0, 0, 1, 1, False, random.Random(1))
        self.assertEqual(rejected, 0)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0][1], 0)

    def test_pawn_family_ignores_piece_only_moves_and_side(self):
        first = "r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq -"
        second = "1r2k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R b KQk -"
        self.assertEqual(sample_fens.pawn_family(first), sample_fens.pawn_family(second))

    def test_pawnless_family_keeps_nonking_piece_placement(self):
        first = "r3k3/8/8/8/8/8/8/R3K3 w - -"
        second = "1r2k3/8/8/8/8/8/8/R3K3 b - -"
        self.assertNotEqual(sample_fens.pawn_family(first), sample_fens.pawn_family(second))

    def test_exclude_inputs_normalize_epd_and_pgn_starts(self):
        fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq -"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            epd = root / "starts.epd"
            pgn = root / "starts.pgn"
            epd.write_text(fen + "\n", encoding="utf-8")
            pgn.write_text(f'[FEN "{fen} 0 1"]\n', encoding="utf-8")
            self.assertEqual(list(sample_fens.iter_start_epds(epd)), [fen])
            self.assertEqual(list(sample_fens.iter_start_epds(pgn)), [fen])
            excluded, families = sample_fens.load_exclusions([epd, pgn])
            self.assertEqual(excluded, {fen})
            self.assertEqual(sum(families.values()), 1)

    def test_parallel_worker_retains_start_accounting_for_empty_games(self):
        game = chess.pgn.Game()
        game.headers["Result"] = "1/2-1/2"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "empty.pgn"
            path.write_text(str(game) + "\n\n", encoding="utf-8")
            opts = {
                "validation_pct": 5.0,
                "test_pct": 5.0,
                "skip_start": 0,
                "skip_end": 6,
                "max_per_phase_per_game": 8,
                "max_per_game": 16,
                "quiet_filter": True,
                "seed": 5316002,
            }
            output, stats = extract_parallel.worker((str(path), 0, path.stat().st_size, opts))
            self.assertEqual(stats["recorded_games"], 1)
            self.assertEqual(stats["skipped"], 1)
            self.assertEqual(len(output), 1)
            self.assertEqual(output[0][2], [])

    def test_threaded_gradient_matches_ordered_serial_reduction(self):
        samples = fit.np.zeros(3, dtype=fit.SAMPLE_DTYPE)
        samples["offset"] = [0, 2, 3]
        samples["base"] = [10.0, -20.0, 30.0]
        samples["target"] = [1.0, 0.0, 0.5]
        samples["count"] = [2, 1, 2]
        events = fit.np.zeros(5, dtype=fit.EVENT_DTYPE)
        events["index"] = [0, 1, 1, 0, 2]
        events["coefficient"] = [1.0, -2.0, 0.5, 3.0, -1.0]
        dataset = type("DatasetFixture", (), {"samples": samples, "events": events})()
        delta = fit.np.asarray([2.0, -1.0, 0.5])
        serial_gradient, serial_loss = fit.gradient(dataset, delta, 1.1, 3, 2)
        with ThreadPoolExecutor(max_workers=2) as executor:
            threaded_gradient, threaded_loss = fit.gradient(
                dataset, delta, 1.1, 3, 2, executor)
        fit.np.testing.assert_array_equal(threaded_gradient, serial_gradient)
        self.assertEqual(threaded_loss, serial_loss)

    def test_sparse_binary_layout_is_frozen(self):
        self.assertEqual(fit.SAMPLE_DTYPE.itemsize, 20)
        self.assertEqual(fit.EVENT_DTYPE.itemsize, 8)

    def test_fit_bounds_preserve_directional_chess_meaning(self):
        names = ["space_bonus[0]", "king_protector[0]",
                 "king_protector[3]", "king_pawn_proximity[0]", "pst_mg[0]"]
        base = fit.np.asarray([3.0, -6.0, -3.0, -2.0, 0.0])
        lower, upper, applied = fit.constrained_bounds(names, base, 512.0)
        self.assertEqual(lower[0], 1.0)
        self.assertEqual(upper[1], -1.0)
        self.assertEqual(upper[2], -1.0)
        self.assertEqual(upper[3], -1.0)
        self.assertEqual(lower[4], -512.0)
        self.assertEqual(upper[4], 512.0)
        self.assertEqual(len(applied), 4)

    def test_texel_sigmoid_is_symmetric(self):
        scores = fit.np.asarray([-200.0, 0.0, 200.0])
        values = fit.sigmoid(scores, 1.0)
        self.assertAlmostEqual(float(values[0] + values[2]), 1.0)
        self.assertEqual(float(values[1]), 0.5)

    def test_man_e20_signal_selects_only_space_events(self):
        samples = fit.np.zeros(2, dtype=fit.SAMPLE_DTYPE)
        samples["offset"] = [0, 3]
        samples["count"] = [3, 2]
        events = fit.np.zeros(5, dtype=fit.EVENT_DTYPE)
        events["index"] = [4, 1, 4, 2, 4]
        events["coefficient"] = [2.0, 99.0, -0.5, 99.0, 3.0]
        dataset = type("DatasetFixture", (), {"samples": samples, "events": events})()
        signal, support = fit_man_e20.selected_signal(dataset, 4, 8)
        fit.np.testing.assert_array_equal(signal, fit.np.asarray([1.5, 3.0]))
        self.assertEqual(support, 3)

    def test_man_e20_scalar_fit_recovers_unclipped_optimum(self):
        base_scores = fit.np.asarray([-50.0, -10.0, 20.0, 80.0])
        signal = fit.np.asarray([1.0, 2.0, -1.0, 0.5])
        expected = 3.25
        targets = fit.sigmoid(base_scores + (expected - 1.0) * signal,
                              fit_man_e20.K_VALUE)
        objective = lambda value: fit_man_e20.scalar_loss(
            base_scores, targets, signal, 1.0, value)
        optimum, loss = fit_man_e20.unconstrained_optimum(objective, 1.0)
        self.assertAlmostEqual(optimum, expected, places=5)
        self.assertLess(loss, 1e-18)

    def test_man_e20_rounds_half_up_after_positive_gate(self):
        self.assertEqual(fit_man_e20.round_half_up(0.5), 1)
        self.assertEqual(fit_man_e20.round_half_up(1.5), 2)
        self.assertEqual(fit_man_e20.round_half_up(-0.5), 0)

    def test_man_e20_gate_checks_aggregate_and_each_phase(self):
        base_phases = fit.np.asarray([0.10] * 5)
        accepted_phases = fit.np.asarray([0.1001] + [0.09] * 4)
        counts = fit.np.asarray([1] * 5)
        self.assertEqual(
            fit_man_e20.gate_failures(
                0.5, 0.1005, 0.1003, base_phases, accepted_phases, counts), [])
        failures = fit_man_e20.gate_failures(
            0.49, 0.1005, 0.1003001,
            base_phases, fit.np.asarray([0.1001001] + [0.09] * 4), counts)
        self.assertEqual(len(failures), 3)


if __name__ == "__main__":
    unittest.main()
