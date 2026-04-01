import argparse
import random
from pathlib import Path

TOTAL_SEATS = 20000


def parse_numbered_benchmark(path: Path) -> list[tuple[str, int, str]]:
    ops: list[tuple[str, int, str]] = []
    with path.open("r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue

            parts = line.split()
            # Expected: BUY <client_id> <seat_id> <request_id>
            if len(parts) != 4 or parts[0] != "BUY":
                continue

            _, client_id, seat_raw, request_id = parts
            try:
                seat_id = int(seat_raw)
            except ValueError:
                continue

            if seat_id < 1 or seat_id > TOTAL_SEATS:
                continue

            ops.append((client_id, seat_id, request_id))

    return ops


def write_numbered_benchmark(path: Path, ops: list[tuple[str, int, str]]) -> None:
    with path.open("w", encoding="utf-8") as f:
        for client_id, seat_id, request_id in ops:
            f.write(f"BUY {client_id} {seat_id} {request_id}\n")


def transform_hotspot(
    ops: list[tuple[str, int, str]], hot_ratio: float, hot_seat_ratio: float, seed: int
) -> list[tuple[str, int, str]]:
    rng = random.Random(seed)
    transformed = list(ops)

    total_ops = len(transformed)
    hot_ops_count = int(total_ops * hot_ratio)

    hot_seat_count = max(1, int(TOTAL_SEATS * hot_seat_ratio))
    hot_seats = list(range(1, hot_seat_count + 1))
    cold_seats = list(range(hot_seat_count + 1, TOTAL_SEATS + 1))

    indices = list(range(total_ops))
    rng.shuffle(indices)
    hot_indices = set(indices[:hot_ops_count])

    for idx, (client_id, _old_seat, request_id) in enumerate(transformed):
        if idx in hot_indices:
            new_seat = rng.choice(hot_seats)
        else:
            new_seat = rng.choice(cold_seats)
        transformed[idx] = (client_id, new_seat, request_id)

    return transformed


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate 80/5 hotspot benchmark for numbered model")
    parser.add_argument("--input", required=True, help="Path to benchmark_numbered.txt")
    parser.add_argument("--output", required=True, help="Path to hotspot output benchmark")
    parser.add_argument("--hot-ratio", type=float, default=0.8, help="Fraction of ops targeting hot seats")
    parser.add_argument("--hot-seat-ratio", type=float, default=0.05, help="Fraction of seat space considered hot")
    parser.add_argument("--seed", type=int, default=42, help="Deterministic random seed")
    args = parser.parse_args()

    if args.hot_ratio <= 0 or args.hot_ratio >= 1:
        raise ValueError("--hot-ratio must be between 0 and 1")
    if args.hot_seat_ratio <= 0 or args.hot_seat_ratio >= 1:
        raise ValueError("--hot-seat-ratio must be between 0 and 1")

    input_path = Path(args.input)
    output_path = Path(args.output)

    ops = parse_numbered_benchmark(input_path)
    if not ops:
        raise ValueError("No valid numbered operations found in input benchmark")

    transformed = transform_hotspot(ops, args.hot_ratio, args.hot_seat_ratio, args.seed)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    write_numbered_benchmark(output_path, transformed)

    hot_seat_count = max(1, int(TOTAL_SEATS * args.hot_seat_ratio))
    print("Generated hotspot benchmark")
    print(f"Input ops: {len(ops)}")
    print(f"Output file: {output_path}")
    print(f"Hot ops ratio: {args.hot_ratio}")
    print(f"Hot seats: 1..{hot_seat_count}")


if __name__ == "__main__":
    main()
