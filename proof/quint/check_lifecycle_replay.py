# SPDX-FileCopyrightText: 2026 tao3k team and Contributors
# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
"""Exhaust the Quint lifecycle graph and replay every reachable state in Scheme."""

from collections import deque
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from process_runner import run

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parent.parent
ACTIONS = ("InstallAdapter", "ReportSuccess", "Plan", "Verify", "Admit", "Decide",
           "Authorize", "StartEffect", "DeliverEffect", "ChangeSource", "Tick", "Revoke",
           "RejectDelivery", "FailDelivery", "UnknownDelivery", "Terminal")
FIELDS = ("revision", "planned", "verified", "admitted", "decided", "granted",
          "grantEpoch", "epoch", "clock", "sealUntil", "grantUntil", "adapterInstalled",
          "reportedSuccess", "effectStarted", "startSafe", "reservationRevision",
          "reservationEpoch", "reservationUntil", "deliveryStatus", "deliveryCalls", "deliverySafe")
# The native atomic entry uses the current 2 GiB / 180-second contract.
NATIVE_BATCH_STEP_BUDGET = 160
NATIVE_REPLAY_TIMEOUT_SECONDS = 180

INVARIANTS = ("TypeOK", "AdmissionIsCurrent", "DecisionRequiresAdmission",
              "GrantRequiresCurrentDecision", "NoUnsafeEffectStart", "NoUnsafeDelivery",
              "DeliveryRequiresStart", "AtMostOneDelivery")
FAULTS = (("unsafeStep", "NoUnsafeEffectStart", "UnsafeStart"),
          ("lateAdmitStep", "AdmissionIsCurrent", "UnsafeLateAdmit"),
          ("earlyGrantStep", "GrantRequiresCurrentDecision", "UnsafeEarlyGrant"),
          ("afterRevokeStep", "NoUnsafeEffectStart", "UnsafeAfterRevoke"),
          ("unsafeDeliveryStep", "NoUnsafeDelivery", "UnsafeDelivery"),
          ("beforeStartStep", "DeliveryRequiresStart", "UnsafeBeforeStart"),
          ("replayStep", "AtMostOneDelivery", "UnsafeReplay"))
SOURCE_CUT = ("justfile", "build.ss", "gerbil.pkg", "testing-interface.ss",
              "testing-observer.ss", "run-test.ss",
              "t/modules/unit/testing-resource-test.ss",
              "proof/quint/AssuranceLifecycle.qnt", "proof/quint/EffectAdmission.qnt",
              "proof/quint/package-lock.json", "proof/quint/check_lifecycle_replay.py",
              "proof/quint/test_lifecycle_replay.py",
              "proof/quint/process_runner.py",
              "modules/assurance/host.ss", "modules/assurance/effect-host.ss",
              "modules/assurance/interface.ss", "t/formal/lifecycle-fixture.ss",
              "t/formal/lifecycle-replay-test.ss", "t/assurance/unit/lifecycle-boundary-test.ss")


def source_hashes():
    return {path: hashlib.sha256((REPO / path).read_bytes()).hexdigest() for path in SOURCE_CUT}


def export_graph(quint, work):
    status, output = run([quint, "compile", str(ROOT / "AssuranceLifecycle.qnt"),
                          "--target", "tlaplus", "--step", "step"], ROOT, "lifecycle-compile")
    start = output.find("-------------------------- MODULE AssuranceLifecycle")
    if status or start < 0 or not output.rstrip().endswith("===="):
        raise RuntimeError(f"Quint compilation failed: {output[-2000:]}")
    # Only a checker intermediate: all transition bodies come from Quint.
    # Expanding the compiled step into its named leaf operators lets TLC label
    # edges without adding a history variable / changing the state quotient.
    model = (ROOT / "AssuranceLifecycle.qnt").read_text()
    unions = dict(re.findall(r"action\s+(\w+)\s*=\s*any\s*\{([^}]+)\}", model))
    def leaf_actions(name):
        if name not in unions:
            return {name}
        return set().union(*(leaf_actions(part.strip()) for part in unions[name].split(",")))
    if leaf_actions("step") != set(ACTIONS):
        raise RuntimeError("Quint action surface changed")
    source = re.sub(r"=+\s*$", "", output[start:])
    source += "\nReplayNext == " + " \\/ ".join(ACTIONS) + "\n====\n"
    (work / "AssuranceLifecycle.tla").write_text(source)
    (work / "safe.cfg").write_text("INIT init\nNEXT ReplayNext\nINVARIANTS " + " ".join(INVARIANTS) + "\n")
    jar = Path(os.environ.get("QUINT_HOME", str(Path.home() / ".quint"))) / "apalache-dist-0.62.1/apalache/lib/apalache.jar"
    if not jar.is_file():
        raise RuntimeError("pinned Quint TLC backend jar is required")
    status, output = run(["java", "-Xmx512m", "-cp", str(jar), "tlc2.TLC", "-workers", "1",
                          "-metadir", str(work / "meta"), "-config", str(work / "safe.cfg"),
                          "-dump", "dot,actionlabels", str(work / "graph"),
                          str(work / "AssuranceLifecycle.tla")], work, "lifecycle-graph")
    counts = re.search(r"(\d+) states generated, (\d+) distinct states found, (\d+) states left on queue", output)
    if status or "Model checking completed. No error has been found." not in output or not counts or int(counts[3]):
        raise RuntimeError(f"incomplete lifecycle graph: exit={status}\n{output[-3000:]}")
    return int(counts[2]), work / "graph.dot"


def read_graph(path, expected):
    nodes, edges, initial = {}, [], []
    for line in path.read_text().splitlines():
        node = re.match(r'\s*"?(-?\d+)"?\s+\[label="([^"]*)"', line)
        if node:
            values = {key: (value == "TRUE" if value in ("TRUE", "FALSE") else int(value))
                      for key, value in re.findall(r"(\w+)\s*\|->\s*(TRUE|FALSE|-?\d+)", node[2])}
            if set(values) != set(FIELDS):
                raise ValueError(f"model state schema changed: {set(values) ^ set(FIELDS)}")
            nodes[node[1]] = values
            if "style = filled" in line or "style=filled" in line:
                initial.append(node[1])
        edge = re.match(r'\s*"?(-?\d+)"?\s*->\s*"?(-?\d+)"?.*label="([^"]+)"', line)
        if edge:
            label = edge[3].split("\\n")[0]
            if label not in ACTIONS:
                raise ValueError(f"unknown TLC action label {label!r}")
            edges.append((edge[1], edge[2], label))
    if len(nodes) != expected or len(initial) != 1 or not edges:
        raise ValueError(f"incomplete graph: nodes={len(nodes)}/{expected} initial={initial} edges={len(edges)}")
    if any(origin not in nodes or target not in nodes for origin, target, _ in edges):
        raise ValueError("edge references a missing state")
    return nodes, edges, initial[0]


def covering_traces(nodes, edges, initial):
    adjacency = {}
    for origin, target, action in edges:
        adjacency.setdefault(origin, []).append((target, action))
    paths = {initial: [("init", nodes[initial])]}
    pending = deque([initial])
    while pending:
        origin = pending.popleft()
        for target, action in adjacency.get(origin, []):
            if target not in paths:
                paths[target] = paths[origin] + [(action, nodes[target])]
                pending.append(target)
    if set(paths) != set(nodes):
        raise ValueError("TLC dump contains unreachable or missing nodes")
    # Ignoring self loops, this bounded lifecycle is a DAG. Its minimum vertex
    # path cover is a bipartite maximum matching. Each path gets a real safe
    # prefix from init, then continues through original TLC edges. No Host is
    # cloned or reset mid-path, and no model state is synthesized in Scheme.
    distinct = {origin: list(dict.fromkeys(target for target, _ in targets if target != origin))
                for origin, targets in adjacency.items()}
    indegree = dict.fromkeys(nodes, 0)
    for targets in distinct.values():
        for target in targets:
            indegree[target] += 1
    queue = deque(node for node in nodes if not indegree[node])
    ordered = []
    while queue:
        origin = queue.popleft()
        ordered.append(origin)
        for target in distinct.get(origin, []):
            indegree[target] -= 1
            if not indegree[target]:
                queue.append(target)
    if len(ordered) != len(nodes):
        raise ValueError("non-stuttering lifecycle graph is not a DAG")
    left, right = {}, {}
    def augment(origin, seen):
        for target in distinct.get(origin, []):
            if target in seen:
                continue
            seen.add(target)
            if target not in right or augment(right[target], seen):
                left[origin], right[target] = target, origin
                return True
        return False
    for origin in nodes:
        augment(origin, set())
    labels = {(origin, target): action for origin, target, action in edges}
    traces = []
    for origin in nodes:
        if origin in right:
            continue
        trace = list(paths[origin])
        while origin in left:
            target = left[origin]
            trace.append((labels[origin, target], nodes[target]))
            origin = target
        traces.append(trace)
    covered = {action for trace in traces for action, _ in trace}
    stutters = {action for origin, target, action in edges if origin == target}
    for action in ACTIONS:
        if action not in covered and action not in stutters:
            origin, target, _ = next(edge for edge in edges if edge[2] == action)
            traces.append(paths[origin] + [(action, nodes[target])])
    # Preserve renewal and terminal stutter witnesses as actual API calls.
    for action in ACTIONS:
        if action not in stutters:
            continue
        origin, target, _ = min((edge for edge in edges if edge[0] == edge[1] and edge[2] == action),
                                key=lambda edge: len(paths[edge[0]]))
        traces.append(paths[origin] + [(action, nodes[target])])
    if {json.dumps(state, sort_keys=True) for trace in traces for _, state in trace} != {
            json.dumps(state, sort_keys=True) for state in nodes.values()}:
        raise ValueError("covering paths do not cover the complete state space")
    return traces


def batches(traces, step_budget=160):
    batch, steps = [], 0
    for trace in traces:
        if len(trace) > step_budget:
            raise ValueError("one trace exceeds the native step budget")
        if batch and steps + len(trace) > step_budget:
            yield batch
            batch, steps = [], 0
        batch.append(trace)
        steps += len(trace)
    if batch:
        yield batch


def sexpr_trace(trace):
    return "(" + " ".join(
        f"({action} (" + " ".join(f"({key} {'#t' if value is True else '#f' if value is False else value})"
                                  for key, value in state.items()) + "))"
        for action, state in trace) + ")"


def negative_traces(quint, work, safe):
    current = lambda q: (q["granted"] == q["revision"] == q["admitted"] == q["decided"]
                         and q["grantEpoch"] == q["epoch"] and q["clock"] < q["grantUntil"])
    selectors = {
        "UnsafeStart": lambda q: q["reportedSuccess"] and not q["effectStarted"] and not current(q),
        "UnsafeLateAdmit": lambda q: q["revision"] == 2 and q["reportedSuccess"] and q["admitted"] == 0,
        "UnsafeEarlyGrant": lambda q: q["revision"] == 2 and q["reportedSuccess"] and q["admitted"] == 0 and q["granted"] == 0 and q["clock"] < 3,
        "UnsafeAfterRevoke": lambda q: q["epoch"] > q["grantEpoch"] and q["grantUntil"] > q["clock"] and q["granted"] == 0 and not q["effectStarted"],
        "UnsafeDelivery": lambda q: q["effectStarted"] and q["deliveryStatus"] == 0 and not current(q),
        "UnsafeBeforeStart": lambda q: q["reportedSuccess"] and not q["effectStarted"],
        "UnsafeReplay": lambda q: q["deliveryStatus"] == 1,
    }
    traces = []
    for step, invariant, fault in FAULTS:
        prefixes = [trace[:index + 1] for trace in safe for index, (_, state) in enumerate(trace)
                    if selectors[fault](state)]
        if not prefixes:
            raise RuntimeError(f"no reachable fault input for {fault}")
        prefix = min(prefixes, key=len)
        state = prefix[-1][1]
        record = "{" + ", ".join(f"{key}: {str(value).lower() if isinstance(value, bool) else value}"
                                  for key, value in state.items()) + "}"
        # Select an actually reachable input, then execute the original Quint
        # fault operator. No guessed output state or random-hit requirement.
        source = (ROOT / "AssuranceLifecycle.qnt").read_text()
        generated = work / f"{fault}.qnt"
        generated.write_text(source.rstrip()[:-1] + f"\n action FaultInit = q' = {record}\n}}\n")
        # Import resolution remains pinned to the same source cut.
        (work / "EffectAdmission.qnt").write_text((ROOT / "EffectAdmission.qnt").read_text())
        status, output = run([quint, "run", str(generated), "--main", "AssuranceLifecycle",
                              "--backend", "typescript", "--seed", "34", "--max-samples", "1",
                              "--n-traces", "1", "--max-steps", "1", "--mbt", "--init", "FaultInit", "--step", fault,
                              "--invariant", invariant, "--verbosity", "1",
                              "--out-itf", str(work / f"{fault}_{{seq}}.json")], REPO, fault)
        if status != 1 or "Invariant violated" not in output:
            raise RuntimeError(f"missing typed counterexample for {fault}: {output[-2000:]}")
        candidates = [json.loads(path.read_text())["states"] for path in work.glob(f"{fault}_*.json")]
        candidates = [trace for trace in candidates if trace[-1]["mbt::actionTaken"] == fault]
        if not candidates:
            raise RuntimeError(f"no failing ITF trace for {fault}")
        trace = list(prefix)
        for row in candidates[0][1:]:
            action, state = row["mbt::actionTaken"], row["q"]
            if action not in set(ACTIONS) | {"init", fault} or set(state) != set(FIELDS):
                raise ValueError("negative model action/state schema changed")
            converted = {}
            for key, value in state.items():
                if isinstance(value, bool):
                    converted[key] = value
                elif isinstance(value, dict) and set(value) == {"#bigint"}:
                    converted[key] = int(value["#bigint"])
                else:
                    raise ValueError("unexpected ITF scalar")
            trace.append((action, converted))
        traces.append(trace)
    return traces


def replay(work, chunk, traces):
    fixture = work / f"traces-{chunk}.scm"
    fixture.write_text("(" + "\n".join(map(sexpr_trace, traces)) + ")\n")
    try:
        status, output = run(["env", f"AITIA_LIFECYCLE_REPLAY={fixture}", "just",
                              "test-scheme-atomic", "formal", "lifecycle-replay-test.ss"],
                             REPO, f"native-lifecycle-{chunk}", timeout=NATIVE_REPLAY_TIMEOUT_SECONDS)
        if status or not re.search(r"^OK$", output, re.MULTILINE):
            raise RuntimeError(f"Scheme replay failed: chunk={chunk} exit={status}\n{output[-8000:]}")
    except (RuntimeError, TimeoutError) as error:
        # Keep the exact failed input after the temporary graph is removed.
        evidence = REPO / ".cache/lifecycle-failures"
        evidence.mkdir(parents=True, exist_ok=True)
        saved = evidence / f"traces-{chunk}.scm"
        saved.write_bytes(fixture.read_bytes())
        (evidence / f"traces-{chunk}.log").write_text(str(error))
        raise RuntimeError(f"{error}\nFAILED-LIFECYCLE-INPUT: {saved}") from error
    return len(traces)


def main():
    hashes = source_hashes()
    quint = os.environ.get("AITIA_QUINT_BIN", str(ROOT / "node_modules/.bin/quint"))
    if subprocess.check_output([quint, "--version"], text=True, timeout=5).strip() != "0.33.0":
        raise RuntimeError("Quint 0.33.0 is required")
    with tempfile.TemporaryDirectory(prefix="aitia-lifecycle-") as temporary:
        work = Path(temporary)
        count, graph = export_graph(quint, work)
        if count != 19042:
            raise RuntimeError(f"lifecycle state quotient changed: {count} != 19042")
        nodes, edges, initial = read_graph(graph, count)
        traces = covering_traces(nodes, edges, initial)
        covered = {edge[2] for edge in edges}
        if covered != set(ACTIONS):
            raise RuntimeError(f"incomplete action coverage: {covered ^ set(ACTIONS)}")
        print(f"LIFECYCLE-GRAPH-OK: states={count} graph-edges={len(edges)} actions={len(covered)} traces={len(traces)}", flush=True)
        faults = negative_traces(quint, work, traces)
        replay(work, "faults", faults)
        completed = 0
        # Four bounded processes use the native resource profile and 180s envelope.
        with ThreadPoolExecutor(max_workers=4) as pool:
            jobs = [pool.submit(replay, work, chunk, batch)
                    for chunk, batch in enumerate(batches(traces, step_budget=NATIVE_BATCH_STEP_BUDGET))]
            try:
                for job in as_completed(jobs):
                    completed += job.result()
                    print(f"LIFECYCLE-REPLAY: traces={completed}/{len(traces)}", flush=True)
            except BaseException:
                for job in jobs:
                    job.cancel()
                raise
        if hashes != source_hashes():
            raise RuntimeError("declared lifecycle source cut changed during verification")
        print("LIFECYCLE-SOURCE-CUT: " + json.dumps(hashes, sort_keys=True), flush=True)
        print(f"LIFECYCLE-SCHEME-OK: states={count}/{count} actions={len(covered)}/16 traces={completed}/{len(traces)} faults={len(faults)}/7", flush=True)


if __name__ == "__main__":
    main()
