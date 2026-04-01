import json
import os
from typing import Any

import pika
from redis import Redis

TOTAL_TICKETS = 20000
RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://guest:guest@localhost:5672/%2F")
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
REQUEST_QUEUE = os.getenv("REQUEST_QUEUE", "tickets.buy")

UNNUMBERED_SOLD_KEY = "tickets:unnumbered:sold"
UNNUMBERED_REQUESTS_KEY = "tickets:unnumbered:requests"
NUMBERED_SEATS_KEY = "tickets:numbered:seats"
NUMBERED_REQUESTS_KEY = "tickets:numbered:requests"

redis_client = Redis.from_url(REDIS_URL, decode_responses=True)

UNNUMBERED_BUY_LUA = """
local sold_key = KEYS[1]
local requests_key = KEYS[2]
local request_id = ARGV[1]
local total_tickets = tonumber(ARGV[2])

if redis.call('HEXISTS', requests_key, request_id) == 1 then
  local current_sold = tonumber(redis.call('GET', sold_key) or '0')
  return {'DUPLICATE', tostring(current_sold)}
end

local current_sold = tonumber(redis.call('GET', sold_key) or '0')
if current_sold >= total_tickets then
  redis.call('HSET', requests_key, request_id, 'SOLD_OUT')
  return {'SOLD_OUT', tostring(current_sold)}
end

local new_sold = redis.call('INCR', sold_key)
if new_sold > total_tickets then
  redis.call('DECR', sold_key)
  redis.call('HSET', requests_key, request_id, 'SOLD_OUT')
  return {'SOLD_OUT', tostring(total_tickets)}
end

redis.call('HSET', requests_key, request_id, 'SUCCESS')
return {'SUCCESS', tostring(new_sold)}
"""

NUMBERED_BUY_LUA = """
local seats_key = KEYS[1]
local requests_key = KEYS[2]
local request_id = ARGV[1]
local seat_id = ARGV[2]
local client_id = ARGV[3]

if redis.call('HEXISTS', requests_key, request_id) == 1 then
  return {'DUPLICATE', seat_id}
end

if redis.call('HEXISTS', seats_key, seat_id) == 1 then
  redis.call('HSET', requests_key, request_id, 'SEAT_TAKEN')
  return {'SEAT_TAKEN', seat_id}
end

redis.call('HSET', seats_key, seat_id, client_id)
redis.call('HSET', requests_key, request_id, 'SUCCESS')
return {'SUCCESS', seat_id}
"""


def process_message(payload: dict[str, Any]) -> dict[str, Any]:
    model = payload.get("model")

    if model == "unnumbered":
        request_id = str(payload["request_id"])
        result = redis_client.eval(
            UNNUMBERED_BUY_LUA,
            2,
            UNNUMBERED_SOLD_KEY,
            UNNUMBERED_REQUESTS_KEY,
            request_id,
            TOTAL_TICKETS,
        )
        return {
            "status": str(result[0]),
            "sold_count": int(result[1]),
            "total_tickets": TOTAL_TICKETS,
        }

    if model == "numbered":
        request_id = str(payload["request_id"])
        seat_id = int(payload["seat_id"])
        client_id = str(payload["client_id"])
        result = redis_client.eval(
            NUMBERED_BUY_LUA,
            2,
            NUMBERED_SEATS_KEY,
            NUMBERED_REQUESTS_KEY,
            request_id,
            seat_id,
            client_id,
        )
        return {"status": str(result[0]), "seat_id": int(result[1])}

    return {"status": "ERROR", "error": "unknown model"}


def main() -> None:
    params = pika.URLParameters(RABBITMQ_URL)
    connection = pika.BlockingConnection(params)
    channel = connection.channel()

    channel.queue_declare(queue=REQUEST_QUEUE, durable=True)
    channel.basic_qos(prefetch_count=50)

    def on_request(ch: Any, method: Any, properties: Any, body: bytes) -> None:
        try:
            payload = json.loads(body.decode("utf-8"))
            response = process_message(payload)
        except Exception as exc:
            response = {"status": "ERROR", "error": str(exc)}

        if properties.reply_to:
            ch.basic_publish(
                exchange="",
                routing_key=properties.reply_to,
                properties=pika.BasicProperties(correlation_id=properties.correlation_id),
                body=json.dumps(response).encode("utf-8"),
            )

        ch.basic_ack(delivery_tag=method.delivery_tag)

    channel.basic_consume(queue=REQUEST_QUEUE, on_message_callback=on_request)
    print(f" [*] Worker waiting on queue '{REQUEST_QUEUE}'", flush=True)
    channel.start_consuming()


if __name__ == "__main__":
    main()
