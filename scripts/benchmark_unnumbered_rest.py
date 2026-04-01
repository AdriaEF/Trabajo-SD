import argparse
import json
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Lock
from urllib import error, request


def send_buy(base_url: str, timeout: float, client_id: str, request_id: str) -> str:
    payload = json.dumps({"client_id": client_id, "request_id": request_id}).encode("utf-8")
    req = request.Request(
        f"{base_url}/buy/unnumbered",
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with request.urlopen(req, timeout=timeout) as response:
            body = response.read().decode("utf-8")
            result = json.loads(body)
            return str(result.get("status", "UNKNOWN"))
    except error.HTTPError:
        return "ERROR"
    except Exception:
        return "ERROR"


def parse_benchmark(path: str) -> list[tuple[str, str]]:
    ops: list[tuple[str, str]] = []
    with open(path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue

            parts = line.split()
            # Expected format: BUY <client_id> <request_id>
            if len(parts) != 3 or parts[0] != "BUY":
                continue

            _, client_id, request_id = parts
            ops.append((client_id, request_id))

    return ops


def run_benchmark(ops: list[tuple[str, str]], base_url: str, concurrency: int, timeout: float) -> Counter:
    stats: Counter = Counter()
    lock = Lock()

    with ThreadPoolExecutor(max_workers=concurrency) as executor:
        futures = [executor.submit(send_buy, base_url, timeout, client_id, request_id) for client_id, request_id in ops]

        for future in as_completed(futures):
            status = future.result()
            with lock:
                stats[status] += 1
                stats["TOTAL"] += 1

    return stats


def main() -> None:
    parser = argparse.ArgumentParser(description="Run unnumbered REST benchmark")
    parser.add_argument("--file", required=True, help="Path to benchmark_unnumbered.txt")
    parser.add_argument("--base-url", default="http://127.0.0.1:8000", help="REST base URL")
    parser.add_argument("--concurrency", type=int, default=64, help="Number of concurrent workers")
    parser.add_argument("--timeout", type=float, default=10.0, help="HTTP timeout in seconds")
    args = parser.parse_args()

    ops = parse_benchmark(args.file)
    if not ops:
        print("No valid operations found in benchmark file.")
        return

    start = time.perf_counter()
    stats = run_benchmark(ops, args.base_url, args.concurrency, args.timeout)
    elapsed = time.perf_counter() - start

    total = stats["TOTAL"]
    throughput = total / elapsed if elapsed > 0 else 0.0

    print("=== Benchmark Results (Unnumbered REST) ===")
    print(f"Operations: {total}")
    print(f"Elapsed seconds: {elapsed:.4f}")
    print(f"Throughput ops/s: {throughput:.2f}")
    print(f"SUCCESS: {stats['SUCCESS']}")
    print(f"SOLD_OUT: {stats['SOLD_OUT']}")
    print(f"DUPLICATE: {stats['DUPLICATE']}")
    print(f"ERROR: {stats['ERROR']}")


if __name__ == "__main__":
    main()
