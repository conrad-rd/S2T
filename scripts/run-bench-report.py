"""Run packaged synthetic suites and retain a reviewable benchmark report."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import uuid

parser = argparse.ArgumentParser()
parser.add_argument("--app", type=Path, default=Path("build/S2T Bench.app"))
parser.add_argument("--seconds", type=int, default=10, choices=range(2, 61))
parser.add_argument("--repeats", type=int, default=3, choices=range(1, 21))
parser.add_argument("--seed", type=int, default=42)
parser.add_argument("--output", type=Path, default=Path("build/bench-verification-report.json"))
parser.add_argument("--save-to-history", action="store_true")
args = parser.parse_args()
app = args.app.resolve()
with (app / "Contents/Info.plist").open("rb") as file:
    metadata = plistlib.load(file)
report = dict(id=str(uuid.uuid4()), created=datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"), schema=1,
    machine=subprocess.check_output(["/usr/bin/sw_vers", "-productVersion"], text=True).strip(),
    processors=os.cpu_count(), memoryGB=int(subprocess.check_output(["/usr/sbin/sysctl", "-n", "hw.memsize"])) / 1_000_000_000,
    settings=dict(kind="synthetic stress", seed=str(args.seed), seconds_per_workload=str(float(args.seconds)),
                  repetitions=str(args.repeats), suites="animations,inputs,reliability"), results=[])

def save():
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_name(args.output.name + "." + report["id"] + ".pending")
    temporary.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    os.replace(temporary, args.output)

for suite in ["animations", "inputs", "reliability"]:
    print(f"Running {suite}, engine build {metadata['S2TBenchmarkEngineBuild']}…", flush=True)
    command = [str(app / "Contents/MacOS/S2TBench"), "--run-suite", suite, "--seconds", str(args.seconds), "--repeats", str(args.repeats), "--seed", str(args.seed)]
    started = len(report["results"])
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for line in process.stdout:
        if not line.startswith("S2TBENCH "):
            continue
        result = json.loads(line[9:])
        result.pop("input", None)
        result.pop("output", None)
        report["results"].append(result)
        save()
        print(f"  {result['status']}: {result['name']}", flush=True)
    code = process.wait()
    if code and not any(r["status"] == "failed" for r in report["results"][started:]):
        report["results"].append(dict(id=str(uuid.uuid4()), suite=suite, name="Suite process failed", status="failed",
            detail=f"Exited with code {code} before reporting the failure.", metrics={}, samples=[]))
    save()

if args.save_to_history:
    destination = Path.home() / "Library/Application Support/S2T Bench/Runs"
    destination.mkdir(parents=True, exist_ok=True)
    output = destination / (report["id"] + ".json")
    temporary = output.with_suffix(".pending")
    with temporary.open("x") as file:
        json.dump(report, file, indent=2, ensure_ascii=False)
        file.write("\n")
    os.replace(temporary, output)
print(f"Saved {args.output}")
sys.exit(1 if any(r["status"] == "failed" for r in report["results"]) else 0)
