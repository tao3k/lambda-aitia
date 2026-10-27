# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Fail-closed controls for the finite lifecycle graph admission gate."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import check_lifecycle_replay as checker


class LifecycleReplayTests(unittest.TestCase):
    def graph(self, suffix='', omitted=None):
        values = {field: False if field.endswith('Safe') or field in
                  ('adapterInstalled', 'reportedSuccess', 'effectStarted') else 0
                  for field in checker.FIELDS if field != omitted}
        label = ', '.join(f'{key} |-> {str(value).upper() if isinstance(value, bool) else value}'
                          for key, value in values.items())
        return f'"1" [label="q = [{label}]", style = filled];\n"1" -> "1" [label="Terminal"];\n' + suffix

    def read(self, source, expected=1):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'graph.dot'
            path.write_text(source)
            return checker.read_graph(path, expected)

    def test_complete_schema(self):
        nodes, edges, initial = self.read(self.graph())
        self.assertEqual(set(nodes[initial]), set(checker.FIELDS))
        self.assertEqual(edges, [('1', '1', 'Terminal')])

    def test_missing_field_is_not_partial_correspondence(self):
        with self.assertRaisesRegex(ValueError, 'schema'):
            self.read(self.graph(omitted='deliveryCalls'))

    def test_missing_node_fails(self):
        with self.assertRaisesRegex(ValueError, 'missing state'):
            self.read(self.graph('"1" -> "2" [label="Verify"];'))

    def test_unknown_action_is_not_scheme_code(self):
        with self.assertRaisesRegex(ValueError, 'unknown TLC action'):
            self.read(self.graph('"1" -> "1" [label="Unexpected"];'))

    def test_incomplete_tlc_count_fails(self):
        with self.assertRaisesRegex(ValueError, 'incomplete graph'):
            self.read(self.graph(), expected=2)

    def test_unreachable_state_fails(self):
        with patch.object(checker, 'ACTIONS', ('Terminal',)):
            with self.assertRaisesRegex(ValueError, 'unreachable'):
                checker.covering_traces({'1': {'clock': 0}, '2': {'clock': 1}},
                                        [('1', '1', 'Terminal')], '1')

    def test_covering_paths_cover_all_states_and_self_loop_action(self):
        with patch.object(checker, 'ACTIONS', ('Verify', 'Terminal')):
            traces = checker.covering_traces({'1': {'clock': 0}, '2': {'clock': 1}},
                                            [('1', '2', 'Verify'), ('2', '2', 'Terminal')], '1')
        self.assertEqual({state['clock'] for trace in traces for _, state in trace}, {0, 1})
        self.assertEqual({action for trace in traces for action, _ in trace}, {'init', 'Verify', 'Terminal'})

    def test_non_stuttering_cycle_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'not a DAG'):
            checker.covering_traces({'1': {'clock': 0}, '2': {'clock': 1}},
                                    [('1', '2', 'Verify'), ('2', '1', 'Revoke')], '1')

    def test_native_batches_preserve_every_trace_and_bound_actual_steps(self):
        traces = [[('init', {})] * size for size in (80, 80, 21, 140, 20)]
        packed = list(checker.batches(traces))
        self.assertEqual([trace for batch in packed for trace in batch], traces)
        self.assertTrue(all(sum(map(len, batch)) <= 160 for batch in packed))
        self.assertEqual([sum(map(len, batch)) for batch in packed], [160, 21, 160])

    def test_smaller_quantum_preserves_atomic_trace_identity_and_order(self):
        traces = [[('init', {})] * size for size in (64, 1, 63, 64)]
        packed = list(checker.batches(traces, step_budget=64))
        flattened = [trace for batch in packed for trace in batch]
        self.assertEqual([sum(map(len, batch)) for batch in packed], [64, 64, 64])
        self.assertEqual(len(flattened), len(traces))
        for original, replayed in zip(traces, flattened):
            self.assertIs(replayed, original)
        with self.assertRaisesRegex(ValueError, 'one trace exceeds'):
            list(checker.batches([[('init', {})] * 65],
                                 step_budget=64))

    def test_replay_propagates_the_current_native_process_budget(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            trace = [('init', {'clock': 0})]
            with patch.object(checker, 'run', return_value=(0, 'OK\n')) as native:
                self.assertEqual(checker.replay(work, 'budget', [trace]), 1)
            self.assertEqual(native.call_args.kwargs['timeout'], 180)
            self.assertEqual((work / 'traces-budget.scm').read_text(),
                             '(' + checker.sexpr_trace(trace) + ')\n')

    def test_single_oversized_trace_is_not_split_or_given_a_larger_timeout(self):
        with self.assertRaisesRegex(ValueError, 'one trace exceeds'):
            list(checker.batches([[('init', {})] * 161]))


if __name__ == '__main__':
    unittest.main()
