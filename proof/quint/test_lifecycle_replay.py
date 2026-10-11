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
                checker.spanning_traces({'1': {'clock': 0}, '2': {'clock': 1}},
                                        [('1', '1', 'Terminal')], '1')

    def test_spanning_paths_cover_all_states_and_self_loop_action(self):
        with patch.object(checker, 'ACTIONS', ('Verify', 'Terminal')):
            traces = checker.spanning_traces({'1': {'clock': 0}, '2': {'clock': 1}},
                                            [('1', '2', 'Verify'), ('2', '2', 'Terminal')], '1')
        self.assertEqual({state['clock'] for trace in traces for _, state in trace}, {0, 1})
        self.assertEqual({action for trace in traces for action, _ in trace}, {'init', 'Verify', 'Terminal'})


if __name__ == '__main__':
    unittest.main()
