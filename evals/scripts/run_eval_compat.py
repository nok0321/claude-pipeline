#!/usr/bin/env python3
"""Windows-compatible trigger evaluation for skill descriptions.

Differs from skill-creator's scripts/run_eval.py in three ways:

1. **Threading-based stdout reader.** run_eval.py uses ``select.select`` on
   a subprocess pipe, which raises ``WinError 10038`` on Windows because the
   Win32 ``select`` API only accepts socket handles. This script uses a
   reader thread feeding a queue.Queue instead — works on both platforms.

2. **No "probe skill" injection.** run_eval.py creates a unique
   ``.claude/commands/<unique>.md`` (now ``.claude/skills/<unique>/SKILL.md``
   in our earlier port) so the eval has its own isolated description. In
   practice claude-opus-4-7 in claude-code 2.1.119 flags such uniquely-named
   skills as **prompt-injection bait** and refuses to invoke them, then
   falls back to whichever real skill matches the query. The eval becomes
   meaningless because the probe is never selected.

   Instead we evaluate the **real, installed skill directly** by checking
   whether claude-p invokes ``Skill`` with ``input.skill`` matching the
   target skill name. The trade-off: we cannot evaluate hypothetical
   description rewrites without temporarily editing the real SKILL.md.
   For Phase 1+ measurement, edit the SKILL.md, run this, then re-run.

3. **Output JSON schema** matches run_eval.py exactly (skill_name,
   description, results[], summary{}) so evals/scripts/aggregate.py
   consumes results uniformly.

Trigger criterion: claude-p emits a ``tool_use`` block with
``name="Skill"`` whose ``input.skill`` field equals (case-insensitive
exact match against) the target skill name.
"""

import argparse
import json
import os
import queue
import subprocess
import sys
import threading
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path


def parse_skill_md(skill_path: Path) -> tuple[str, str, str]:
    """Parse SKILL.md frontmatter; return (name, description, body)."""
    skill_file = skill_path / "SKILL.md"
    text = skill_file.read_text(encoding="utf-8")

    if not text.startswith("---"):
        raise ValueError(f"No frontmatter in {skill_file}")

    parts = text.split("---", 2)
    if len(parts) < 3:
        raise ValueError(f"Malformed frontmatter in {skill_file}")

    frontmatter_text = parts[1]
    body = parts[2].lstrip("\n")

    name: str | None = None
    description: str | None = None
    desc_lines: list[str] = []
    in_desc_block = False

    for line in frontmatter_text.splitlines():
        if not line.strip():
            in_desc_block = False
            continue

        if line.startswith("name:"):
            name = line.split(":", 1)[1].strip()
            in_desc_block = False
        elif line.startswith("description:"):
            after = line.split(":", 1)[1].strip()
            if after in ("|", ">", "|-", ">-", "|+", ">+"):
                in_desc_block = True
            else:
                description = after
                in_desc_block = False
        elif in_desc_block and (line.startswith(" ") or line.startswith("\t")):
            desc_lines.append(line.strip())
        else:
            in_desc_block = False

    if desc_lines and description is None:
        description = " ".join(desc_lines)

    if not name or not description:
        raise ValueError(
            f"Missing name or description in {skill_file} frontmatter"
        )

    return name, description, body


def find_project_root() -> Path:
    """Walk up from cwd to find .claude/."""
    current = Path.cwd()
    for parent in [current, *current.parents]:
        if (parent / ".claude").is_dir():
            return parent
    return current


def _stdout_reader(stream, q: "queue.Queue") -> None:
    """Read stream and push bytes chunks; sentinel None on EOF/error."""
    try:
        while True:
            chunk = stream.read1(8192) if hasattr(stream, "read1") else stream.read(8192)
            if not chunk:
                break
            q.put(chunk)
    except Exception:
        pass
    finally:
        q.put(None)


def run_single_query(
    query: str,
    target_skill_name: str,
    timeout: int,
    project_root: str,
    model: str | None = None,
) -> bool:
    """Return True iff claude-p invokes Skill with input.skill == target."""
    cmd = [
        "claude",
        "-p", query,
        "--output-format", "stream-json",
        "--verbose",
        "--include-partial-messages",
    ]
    if model:
        cmd.extend(["--model", model])

    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}

    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        cwd=project_root,
        env=env,
        bufsize=0,
    )

    stdout_queue: "queue.Queue" = queue.Queue()
    reader_thread = threading.Thread(
        target=_stdout_reader,
        args=(process.stdout, stdout_queue),
        daemon=True,
    )
    reader_thread.start()

    target_lower = target_skill_name.lower()
    triggered = False
    start_time = time.time()
    buffer = ""
    pending_skill_block = False
    accumulated_json = ""

    try:
        while time.time() - start_time < timeout:
            try:
                chunk = stdout_queue.get(timeout=1.0)
            except queue.Empty:
                if process.poll() is not None and stdout_queue.empty():
                    break
                continue

            if chunk is None:
                break

            buffer += chunk.decode("utf-8", errors="replace")

            while "\n" in buffer:
                line, buffer = buffer.split("\n", 1)
                line = line.strip()
                if not line:
                    continue

                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue

                # Stream-event path (early, partial JSON)
                if event.get("type") == "stream_event":
                    se = event.get("event", {})
                    se_type = se.get("type", "")

                    if se_type == "content_block_start":
                        cb = se.get("content_block", {})
                        if cb.get("type") == "tool_use" and cb.get("name") == "Skill":
                            pending_skill_block = True
                            accumulated_json = ""
                        else:
                            pending_skill_block = False

                    elif se_type == "content_block_delta" and pending_skill_block:
                        delta = se.get("delta", {})
                        if delta.get("type") == "input_json_delta":
                            accumulated_json += delta.get("partial_json", "")

                    elif se_type == "content_block_stop" and pending_skill_block:
                        pending_skill_block = False
                        # Try to parse the accumulated input JSON
                        try:
                            parsed = json.loads(accumulated_json)
                            if isinstance(parsed, dict):
                                skill_arg = parsed.get("skill", "")
                                if isinstance(skill_arg, str) and skill_arg.lower() == target_lower:
                                    triggered = True
                        except json.JSONDecodeError:
                            # Fall back to substring search
                            if f'"{target_skill_name}"' in accumulated_json or \
                               f"'{target_skill_name}'" in accumulated_json:
                                triggered = True

                # Fallback: full assistant message tool_use blocks
                elif event.get("type") == "assistant":
                    message = event.get("message", {})
                    for content_item in message.get("content", []):
                        if content_item.get("type") != "tool_use":
                            continue
                        if content_item.get("name") != "Skill":
                            continue
                        tool_input = content_item.get("input", {})
                        skill_arg = tool_input.get("skill", "")
                        if isinstance(skill_arg, str) and skill_arg.lower() == target_lower:
                            triggered = True

                elif event.get("type") == "result":
                    return triggered

        return triggered
    finally:
        if process.poll() is None:
            process.kill()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass


def run_eval(
    eval_set: list[dict],
    skill_name: str,
    description: str,
    num_workers: int,
    timeout: int,
    project_root: Path,
    runs_per_query: int = 1,
    trigger_threshold: float = 0.5,
    model: str | None = None,
) -> dict:
    """Run the full eval set and return results."""
    with ProcessPoolExecutor(max_workers=num_workers) as executor:
        future_to_info = {}
        for item in eval_set:
            for run_idx in range(runs_per_query):
                future = executor.submit(
                    run_single_query,
                    item["query"],
                    skill_name,
                    timeout,
                    str(project_root),
                    model,
                )
                future_to_info[future] = (item, run_idx)

        query_triggers: dict[str, list[bool]] = {}
        query_items: dict[str, dict] = {}
        for future in as_completed(future_to_info):
            item, _ = future_to_info[future]
            q = item["query"]
            query_items[q] = item
            query_triggers.setdefault(q, [])
            try:
                query_triggers[q].append(future.result())
            except Exception as e:
                print(f"Warning: query failed: {e}", file=sys.stderr)
                query_triggers[q].append(False)

    results = []
    for q, triggers in query_triggers.items():
        item = query_items[q]
        rate = sum(triggers) / len(triggers)
        should = item["should_trigger"]
        did_pass = (rate >= trigger_threshold) if should else (rate < trigger_threshold)
        results.append({
            "query": q,
            "should_trigger": should,
            "trigger_rate": rate,
            "triggers": sum(triggers),
            "runs": len(triggers),
            "pass": did_pass,
        })

    passed = sum(1 for r in results if r["pass"])
    return {
        "skill_name": skill_name,
        "description": description,
        "results": results,
        "summary": {
            "total": len(results),
            "passed": passed,
            "failed": len(results) - passed,
        },
    }


def main():
    parser = argparse.ArgumentParser(
        description="Trigger evaluation for an installed skill (Windows-compatible, no probe)."
    )
    parser.add_argument("--eval-set", required=True, help="Path to eval set JSON")
    parser.add_argument("--skill-path", required=True,
                        help="Path to the real installed skill directory (its name is read and used as the target)")
    parser.add_argument("--num-workers", type=int, default=10)
    parser.add_argument("--timeout", type=int, default=30, help="Per-query seconds")
    parser.add_argument("--runs-per-query", type=int, default=3)
    parser.add_argument("--trigger-threshold", type=float, default=0.5)
    parser.add_argument("--model", default=None)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    eval_set = json.loads(Path(args.eval_set).read_text(encoding="utf-8"))
    skill_path = Path(args.skill_path)

    if not (skill_path / "SKILL.md").exists():
        print(f"Error: No SKILL.md at {skill_path}", file=sys.stderr)
        sys.exit(1)

    name, description, _ = parse_skill_md(skill_path)
    project_root = find_project_root()

    if args.verbose:
        print(f"Evaluating skill='{name}' against {len(eval_set)} queries...", file=sys.stderr)
        print(f"  description (first 100 chars): {description[:100]}...", file=sys.stderr)

    output = run_eval(
        eval_set=eval_set,
        skill_name=name,
        description=description,
        num_workers=args.num_workers,
        timeout=args.timeout,
        project_root=project_root,
        runs_per_query=args.runs_per_query,
        trigger_threshold=args.trigger_threshold,
        model=args.model,
    )

    if args.verbose:
        s = output["summary"]
        print(f"Results: {s['passed']}/{s['total']} passed", file=sys.stderr)
        for r in output["results"]:
            tag = "PASS" if r["pass"] else "FAIL"
            print(
                f"  [{tag}] rate={r['triggers']}/{r['runs']} expected={r['should_trigger']}: {r['query'][:70]}",
                file=sys.stderr,
            )

    print(json.dumps(output, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
