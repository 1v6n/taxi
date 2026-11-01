#!/usr/bin/env python3
"""Stage Verification Regression Runner with Parallel Execution Support.

Executes tests defined in the testbench, logs outputs to logs/ and waves to waves/,
evaluates scoreboard results, and supports concurrent execution (-j / --jobs).
"""

import argparse
import concurrent.futures
import csv
import fnmatch
import os
import re
import shutil
import subprocess
import sys
import time

# ANSI color codes for terminal formatting
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
BOLD = "\033[1m"
RESET = "\033[0m"


def parse_args():
    parser = argparse.ArgumentParser(
        description="Run serial_to_parallel verification regression suite."
    )
    parser.add_argument(
        "--stage",
        type=int,
        default=5,
        help="Verification stage number (default: 5)",
    )
    parser.add_argument(
        "--tests",
        type=str,
        default="all",
        help="Filter pattern for tests (e.g. 'all', 'TC1*', 'parity', 'TC1,TC2')",
    )
    parser.add_argument(
        "--simulator",
        choices=["verilator", "vivado", "xsim"],
        default="verilator",
        help="Simulator to use (default: verilator)",
    )
    parser.add_argument(
        "-j",
        "--jobs",
        type=int,
        default=4,
        help="Number of concurrent simulation jobs (default: 4)",
    )
    parser.add_argument(
        "--seed",
        type=str,
        default="",
        help="Base simulation seed (default: epoch timestamp)",
    )
    parser.add_argument(
        "--no-waves",
        action="store_true",
        help="Disable waveform dumping for faster regression",
    )
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Clean previous build and simulation artifacts before starting",
    )
    parser.add_argument(
        "--stop-on-failure",
        action="store_true",
        help="Abort regression immediately on first test failure",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List all discovered tests and exit",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print simulation commands without running them",
    )
    return parser.parse_args()


def discover_tests(verif_dir, stage):
    """Discover tests implemented in stage directory and registered in tb_top.sv."""
    stage_dir = os.path.join(verif_dir, f"stage_{stage}")
    tests_dir = os.path.join(stage_dir, "tests")
    tb_top_path = os.path.join(stage_dir, "tb_top.sv")

    # Read registered test names from tb_top.sv
    registered_tests = set()
    if os.path.isfile(tb_top_path):
        with open(tb_top_path, "r", errors="ignore") as f:
            content = f.read()
            # Extract case block
            m = re.search(r"case\s*\(\s*test_name\s*\)(.*?)endcase", content, re.DOTALL)
            if m:
                case_content = m.group(1)
                for test_token in re.findall(r'"([A-Za-z0-9_]+)"', case_content):
                    registered_tests.add(test_token)

    # Discover .sv files in tests/
    discovered = []
    if os.path.isdir(tests_dir):
        for fname in sorted(os.listdir(tests_dir)):
            if fname.endswith(".sv") and fname != "base_test.sv":
                base_name = fname[:-3]
                # Extract numeric ID if present (e.g. TC1 -> 1, sanity_test -> 0)
                m = re.match(r"TC(\d+)_", base_name, re.IGNORECASE)
                tid = int(m.group(1)) if m else (0 if "sanity" in base_name.lower() else 999)
                is_registered = base_name in registered_tests or not registered_tests
                discovered.append({
                    "id": tid,
                    "file_name": base_name,
                    "test_name": base_name,
                    "registered": is_registered,
                    "path": os.path.join(tests_dir, fname),
                })

    discovered.sort(key=lambda t: t["id"])
    return discovered


def filter_tests(tests, pattern):
    """Filter tests by pattern or comma-separated list."""
    if pattern.strip().lower() in ("all", "*"):
        return tests

    patterns = [p.strip().lower() for p in pattern.split(",") if p.strip()]
    matched = []
    for t in tests:
        fname = t["file_name"].lower()
        tname = t["test_name"].lower()
        tid_str = f"tc{t['id']}"
        for pat in patterns:
            if fnmatch.fnmatch(fname, pat) or fnmatch.fnmatch(tname, pat) or pat in fname or pat == tid_str:
                matched.append(t)
                break
    return matched


def evaluate_log(log_content, returncode):
    """Determine whether simulation PASSED or FAILED based on log analysis."""
    if returncode != 0:
        return False, 0, 1, f"Process exited with non-zero exit code ({returncode})"

    # Check for fatal / error patterns
    fatal_patterns = [
        r"%Error:",
        r"\$fatal",
        r"Simulation timeout reached",
        r"\[SCB\].*?(?:mismatch|timeout|error|incomplete)",
        r"Error:\s*Transaction\s+mismatched",
    ]
    for pat in fatal_patterns:
        m = re.search(pat, log_content, re.IGNORECASE)
        if m:
            return False, 0, 1, f"Matched error pattern: '{m.group(0)}'"

    # Extract matches and mismatches
    matches = 0
    mismatches = 0
    m_match = re.search(r"(?:Matches\s*:\s*|:\s*)(\d+)\s+matches", log_content, re.IGNORECASE)
    if not m_match:
        m_match = re.search(r"Matches\s*:\s*(\d+)", log_content, re.IGNORECASE)
    if m_match:
        matches = int(m_match.group(1))
    else:
        match_lines = re.findall(r"\[SCB\s*\]\s+(?:MATCH|PASS)\s+#\d+", log_content, re.IGNORECASE)
        matches = len(match_lines)

    m_mismatch = re.search(r"(\d+)\s+mismatches", log_content, re.IGNORECASE)
    if not m_mismatch:
        m_mismatch = re.search(r"Mismatches\s*:\s*(\d+)", log_content, re.IGNORECASE)
    if m_mismatch:
        mismatches = int(m_mismatch.group(1))

    # Explicit PASS checks
    has_test_passed = bool(re.search(r"\[TEST\].*?PASSED|STATUS\s*:\s*PASSED", log_content, re.IGNORECASE))
    has_finish = bool(re.search(r"(\$finish called|Verilog \$finish|\$finish at)", log_content, re.IGNORECASE))

    if (has_test_passed or has_finish) and mismatches == 0 and matches > 0:
        return True, matches, mismatches, "Scoreboard PASS"

    return False, matches, mismatches, "Missing explicit completion or scoreboard PASS"


def run_single_test(test, verif_dir, stage, simulator, base_seed, dump_waves, dry_run):
    """Run one test instance, capture its log and waveform, and return result dict."""
    file_name = test["file_name"]
    test_id = test["id"]
    test_seed = str(int(base_seed) + test_id)

    stage_dir = os.path.join(verif_dir, f"stage_{stage}")
    stage_logs_dir = os.path.join(stage_dir, "logs")
    stage_waves_dir = os.path.join(stage_dir, "waves")
    root_logs_dir = os.path.join(verif_dir, "logs")
    root_waves_dir = os.path.join(verif_dir, "waves")

    for d in (stage_logs_dir, stage_waves_dir, root_logs_dir, root_waves_dir):
        os.makedirs(d, exist_ok=True)

    log_file = os.path.join(stage_logs_dir, f"{file_name}.log")
    vcd_file = os.path.join(stage_waves_dir, f"{file_name}.vcd") if dump_waves else None

    # Construct command
    env = os.environ.copy()
    env["STAGE"] = str(stage)

    if simulator == "verilator":
        binary_path = os.path.join(verif_dir, "obj_dir", "Vtb_top")
        cmd = [
            binary_path,
            f"+verilator+seed+{test_seed}",
            f"+SEED={test_seed}",
            f"+TEST_NAME={file_name}",
        ]
        if dump_waves and vcd_file:
            cmd.extend([f"+VCD={vcd_file}", f"+FST={vcd_file}"])
    elif simulator == "xsim":
        xsim_script = os.path.join(verif_dir, "tools", "run_xsim.sh")
        env["SKIP_BUILD"] = "1"
        cmd = [
            xsim_script,
            "tb_top",
            f"+SEED={test_seed}",
            f"+TEST_NAME={file_name}",
        ]
        if dump_waves and vcd_file:
            cmd.extend([f"+VCD={vcd_file}", f"+FST={vcd_file}"])
    else:
        # Vivado
        vivado_script = os.path.join(verif_dir, "tools", "run_vivado_sim.sh")
        extra_args = f"+TEST_NAME={file_name}"
        if dump_waves and vcd_file:
            extra_args += f" +VCD={vcd_file} +FST={vcd_file}"
        cmd = [
            vivado_script,
            "--stage", str(stage),
            "--top", "tb_top",
            "--seed", test_seed,
            "--args", extra_args,
        ]

    if dry_run:
        return {
            "id": test_id,
            "file_name": file_name,
            "status": "DRY_RUN",
            "matches": 0,
            "mismatches": 0,
            "time": 0.0,
            "reason": "Dry run execution",
            "log": log_file,
            "wave": vcd_file,
        }

    t_start = time.time()
    with open(log_file, "w") as lf:
        proc = subprocess.run(
            cmd,
            cwd=verif_dir,
            env=env,
            stdout=lf,
            stderr=subprocess.STDOUT,
            text=True,
        )
    elapsed = time.time() - t_start

    # Mirror log and wave to root verification/logs and verification/waves
    try:
        shutil.copy2(log_file, os.path.join(root_logs_dir, f"{file_name}.log"))
        if dump_waves and vcd_file and os.path.isfile(vcd_file):
            shutil.copy2(vcd_file, os.path.join(root_waves_dir, f"{file_name}.vcd"))
    except Exception:
        pass

    with open(log_file, "r", errors="replace") as lf:
        log_content = lf.read()

    is_pass, matches, mismatches, reason = evaluate_log(log_content, proc.returncode)

    return {
        "id": test_id,
        "file_name": file_name,
        "status": "PASSED" if is_pass else "FAILED",
        "matches": matches,
        "mismatches": mismatches,
        "time": elapsed,
        "reason": reason,
        "log": log_file,
        "wave": vcd_file,
    }


def main():
    args = parse_args()
    script_dir = os.path.dirname(os.path.abspath(__file__))
    verif_dir = os.path.dirname(script_dir)

    base_seed = args.seed if args.seed else str(int(time.time()))

    all_tests = discover_tests(verif_dir, args.stage)
    if args.list:
        print(f"\n{BOLD}Stage {args.stage} tests:{RESET}")
        print(f"{'ID':<4} | {'Test Name':<32} | {'Registered in tb_top'}")
        print("-" * 60)
        for t in all_tests:
            reg_str = f"{GREEN}Yes{RESET}" if t["registered"] else f"{YELLOW}No{RESET}"
            print(f"{t['id']:<4} | {t['file_name']:<32} | {reg_str}")
        print(f"\nTotal: {len(all_tests)}\n")
        return

    selected_tests = filter_tests(all_tests, args.tests)
    if not selected_tests:
        print(f"{YELLOW}No tests matched pattern: '{args.tests}'{RESET}")
        return

    # Clean if requested
    if args.clean and not args.dry_run:
        print(f"{YELLOW}Cleaning build artifacts...{RESET}")
        subprocess.run(["make", "clean"], cwd=verif_dir, stdout=subprocess.DEVNULL)

    # Build once before launching parallel workers
    if args.simulator == "verilator" and not args.dry_run:
        print(f"{BOLD}Building Verilator target (stage {args.stage})...{RESET}")
        build_env = os.environ.copy()
        build_env["STAGE"] = str(args.stage)
        build_env["BUILD_ONLY"] = "1"
        build_cmd = [os.path.join(script_dir, "run_sim.sh"), "tb_top"]
        build_proc = subprocess.run(build_cmd, cwd=verif_dir, env=build_env)
        if build_proc.returncode != 0:
            print(f"{RED}{BOLD}Build failed.{RESET}", file=sys.stderr)
            sys.exit(1)
    elif args.simulator == "xsim" and not args.dry_run:
        print(f"{BOLD}Building XSim target (stage {args.stage})...{RESET}")
        build_env = os.environ.copy()
        build_env["STAGE"] = str(args.stage)
        build_env["BUILD_ONLY"] = "1"
        build_cmd = [os.path.join(script_dir, "run_xsim.sh"), "tb_top"]
        build_proc = subprocess.run(build_cmd, cwd=verif_dir, env=build_env)
        if build_proc.returncode != 0:
            print(f"{RED}{BOLD}Build failed.{RESET}", file=sys.stderr)
            sys.exit(1)

    dump_waves = not args.no_waves
    jobs = max(1, args.jobs)
    if args.simulator in ("vivado", "xsim") and jobs > 1:
        print(f"{YELLOW}Warning: {args.simulator} engine does not support concurrent snapshot execution in the same directory (shm_open collision); falling back to -j 1.{RESET}")
        jobs = 1

    print(f"{BOLD}Running stage {args.stage} regression: {len(selected_tests)} tests ({args.simulator}, jobs={jobs}, seed={base_seed}){RESET}\n")

    reg_start_time = time.time()
    results = []
    passed_count = 0
    failed_count = 0

    if jobs == 1 or len(selected_tests) == 1:
        # Sequential execution with direct output
        for idx, test in enumerate(selected_tests, 1):
            fname = test["file_name"]
            print(f"[{idx:2d}/{len(selected_tests):2d}] {BOLD}{fname:<28}{RESET} ... ", end="", flush=True)
            res = run_single_test(test, verif_dir, args.stage, args.simulator, base_seed, dump_waves, args.dry_run)
            results.append(res)
            st_color = GREEN if res["status"] == "PASSED" else RED
            print(f"{st_color}{BOLD}{res['status']}{RESET} ({res['time']:5.2f}s) matches={res['matches']}")
            if res["status"] == "PASSED":
                passed_count += 1
            else:
                failed_count += 1
                print(f"  Error: {res['reason']}")
                print(f"  Log:   {res['log']}")
                if args.stop_on_failure:
                    print(f"\n{RED}{BOLD}Stopped on first failure.{RESET}")
                    break
    else:
        # Parallel execution using ThreadPoolExecutor
        completed_count = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as executor:
            future_to_test = {
                executor.submit(
                    run_single_test, test, verif_dir, args.stage, args.simulator, base_seed, dump_waves, args.dry_run
                ): test
                for test in selected_tests
            }

            for future in concurrent.futures.as_completed(future_to_test):
                completed_count += 1
                res = future.result()
                results.append(res)
                fname = res["file_name"]
                st_color = GREEN if res["status"] == "PASSED" else RED
                if res["status"] == "PASSED":
                    passed_count += 1
                else:
                    failed_count += 1

                print(
                    f"[{completed_count:2d}/{len(selected_tests):2d}] {BOLD}{fname:<28}{RESET} "
                    f"-> {st_color}{BOLD}{res['status']:<6}{RESET} ({res['time']:5.2f}s) matches={res['matches']}"
                )
                if res["status"] != "PASSED":
                    print(f"  Error: {res['reason']}")
                    print(f"  Log:   {res['log']}")

    total_duration = time.time() - reg_start_time

    # Sort results by test ID for clean reporting
    results.sort(key=lambda r: r["id"])

    # Print summary table
    print(f"\n{BOLD}--- Stage {args.stage} Summary ---{RESET}")
    print(f"{'ID':<4} | {'Test Name':<28} | {'Status':<8} | {'Matches':<8} | {'Time':<7} | {'Log'}")
    print("-" * 74)
    for r in results:
        st_color = GREEN if r["status"] == "PASSED" else RED
        log_name = os.path.basename(r["log"])
        print(f"{r['id']:<4} | {r['file_name']:<28} | {st_color}{r['status']:<8}{RESET} | {r['matches']:<8} | {r['time']:5.2f}s | {log_name}")
    print("-" * 74)
    summary_color = GREEN if failed_count == 0 else RED
    print(
        f"Total: {len(results)} | {GREEN}Passed: {passed_count}{RESET} | "
        f"{summary_color}Failed: {failed_count}{RESET} | Time: {total_duration:5.2f}s\n"
    )

    if failed_count > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
