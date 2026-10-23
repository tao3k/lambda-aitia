# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""The correspondence runner must fail closed on schema and checker failures."""

import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2] / "proof/quint"
sys.path.insert(0, str(ROOT))
SPEC = importlib.util.spec_from_file_location("quint_replay", ROOT / "check_scheme_replay.py")
replay = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(replay)


def initial():
    return {"mbt::actionTaken": "init", "q": {
        "work": {"active": True, "queued": True, "cancelRequested": False},
        "known": False, "reviewed": False, "retired": False, "lateFound": False,
        "gapFound": False, "ingressOpen": True, "epoch": {"#bigint": "0"},
        "grantEpoch": {"#bigint": "0"}, "pending": False, "attempted": False,
        "rejectedAfterRetirement": False, "startedAfterRetirement": False}}


class QuintReplayTest(unittest.TestCase):
    def test_all_projected_slots_and_itf_integer_are_data(self):
        row = replay.state_row(initial())
        self.assertIn("(authority-epoch 0)", row)
        self.assertIn("(cancellation-requested? #f)", row)
        self.assertEqual(row.count("?") + row.count("-epoch"), len(replay.FIELDS))

    def test_added_model_field_cannot_be_silently_ignored(self):
        state = initial()
        state["q"]["newAuthority"] = True
        with self.assertRaisesRegex(ValueError, "schema changed"):
            replay.state_row(state)

    def test_missing_work_field_cannot_be_silently_ignored(self):
        state = initial()
        del state["q"]["work"]["queued"]
        with self.assertRaisesRegex(ValueError, "schema changed"):
            replay.state_row(state)

    def test_action_text_cannot_be_executed(self):
        state = initial()
        state["mbt::actionTaken"] = "init) (error injected) ("
        with self.assertRaisesRegex(ValueError, "unknown Quint action"):
            replay.state_row(state)

    def test_non_scalar_itf_value_is_rejected(self):
        with self.assertRaises(ValueError):
            replay.scalar({"#set": []})

    def test_tool_failure_is_not_a_negative_control(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(replay, "run", return_value=(2, "Invariant violated")):
            with self.assertRaisesRegex(RuntimeError, "unexpected Quint result"):
                replay.generate("quint", Path(directory), "fault", "unfencedStep", "RetiredIsFenced", 1)

    def test_success_without_completed_output_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(replay, "run", return_value=(0, "[ok] No violation found")):
            with self.assertRaisesRegex(RuntimeError, "incomplete trace output"):
                replay.generate("quint", Path(directory), "safe", "step", "TypeOK", 1)

    def test_success_exit_without_success_marker_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(replay, "run", return_value=(0, "tool error")):
            with self.assertRaisesRegex(RuntimeError, "unexpected Quint result"):
                replay.generate("quint", Path(directory), "safe", "step", "TypeOK", 1)


if __name__ == "__main__":
    unittest.main()
