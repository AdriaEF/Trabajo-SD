import argparse
import json
import time
import uuid
from collections import Counter
from typing import Any

import pika


def parse_unnumbered(path: str) -> list[dict[str, Any]]:
    ops: list[dict[str, Any]] = []
    with open(path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) != 3 or parts[0] != "BUY":
                continue
            _, client_id, request_id = parts
            ops.append({"model": "unnumbered", "client_id": client_id, "request_id": request_id})
    return ops


def parse_numbered(path: str) -> list[dict[str, Any]]:
    ops: list[dict[str, Any]] = []
    with open(path, "r", encoding="utf-8") as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) != 4 or parts[0] != "BUY":
                continue
            _, client_id, seat_raw, request_id = parts
            try:
                seat_id = int(seat_raw)
            except ValueError:
                continue
            ops.append(
                {
                    "model": "numbered",
                    "client_id": client_id,
                    "seat_id": seat_id,
                    "request_id": request_id,
                }
            )
    return ops


class RpcClient:
    def __init__(self, rabbitmq_url: str, request_queue: str) -> None:
        self.connection = pika.BlockingConnection(pika.URLParameters(rabbitmq_url))
        self.channel = self.connection.channel()
        self.request_queue = request_queue

        result = self.channel.queue_declare(queue="", exclusive=True)
        self.callback_queue = result.method.queue
        self.responses: dict[str, dict[str, Any]] = {}

        self.channel.basic_consume(
            queue=self.callback_queue,
            on_message_callback=self.on_response,
            auto_ack=True,
        )
        self.pending: set[str] = set()
        self.stats: Counter = Counter()

    def on_response(self, ch: Any, method: Any, props: Any, body: bytes) -> None:
        if props.correlation_id:
            self.responses[props.correlation_id] = json.loads(body.decode("utf-8"))

    def publish(self, message: dict[str, Any]) -> str:
        correlation_id = str(uuid.uuid4())
        self.pending.add(correlation_id)
        self.channel.basic_publish(
            exchange="",
            routing_key=self.request_queue,
            properties=pika.BasicProperties(
                reply_to=self.callback_queue,
                correlation_id=correlation_id,
                delivery_mode=2,
            ),
            body=json.dumps(message).encode("utf-8"),
        )
        return correlation_id

    def process_events(self, time_limit: float = 0.1) -> None:
        self.connection.process_data_events(time_limit=time_limit)

    def collect_ready_responses(self) -> int:
        processed = 0
        ready_ids = list(self.responses.keys())
        for correlation_id in ready_ids:
            response = self.responses.pop(correlation_id)
            status = str(response.get("status", "UNKNOWN"))
            self.stats[status] += 1
            self.stats["TOTAL"] += 1
            self.pending.discard(correlation_id)
            processed += 1
        return processed

    def run(self, ops: list[dict[str, Any]], inflight: int) -> Counter:
        next_index = 0
        total_ops = len(ops)

        while next_index < total_ops and len(self.pending) < inflight:
            self.publish(ops[next_index])
            next_index += 1

        while self.pending:
            self.process_events(time_limit=0.1)
            self.collect_ready_responses()

            while next_index < total_ops and len(self.pending) < inflight:
                self.publish(ops[next_index])
                next_index += 1

        return self.stats

    def close(self) -> None:
        self.connection.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Run RabbitMQ benchmark (concurrent RPC mode)")
    parser.add_argument("--model", choices=["unnumbered", "numbered"], required=True)
    parser.add_argument("--file", required=True)
    parser.add_argument("--rabbitmq-url", default="amqp://guest:guest@localhost:5672/%2F")
    parser.add_argument("--request-queue", default="tickets.buy")
    parser.add_argument("--inflight", type=int, default=256, help="Maximum requests in flight")
    args = parser.parse_args()

    if args.model == "unnumbered":
        ops = parse_unnumbered(args.file)
    else:
        ops = parse_numbered(args.file)

    if not ops:
        print("No valid operations found in benchmark file.")
        return

    if args.inflight < 1:
        print("--inflight must be >= 1")
        return

    client = RpcClient(args.rabbitmq_url, args.request_queue)

    start = time.perf_counter()
    try:
        stats = client.run(ops, args.inflight)
    finally:
        client.close()
    elapsed = time.perf_counter() - start

    total = stats["TOTAL"]
    throughput = total / elapsed if elapsed > 0 else 0.0

    print(f"=== Benchmark Results (RabbitMQ {args.model}) ===")
    print(f"Operations: {total}")
    print(f"Elapsed seconds: {elapsed:.4f}")
    print(f"Throughput ops/s: {throughput:.2f}")
    print(f"SUCCESS: {stats['SUCCESS']}")
    print(f"SOLD_OUT: {stats['SOLD_OUT']}")
    print(f"SEAT_TAKEN: {stats['SEAT_TAKEN']}")
    print(f"DUPLICATE: {stats['DUPLICATE']}")
    print(f"ERROR: {stats['ERROR']}")


if __name__ == "__main__":
    main()
