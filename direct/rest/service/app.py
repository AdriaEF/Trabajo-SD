import os
from enum import Enum

from fastapi import FastAPI
from pydantic import BaseModel, Field
from redis import Redis

TOTAL_TICKETS = 20000
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379/0")
WORKER_ID = os.getenv("WORKER_ID", "worker-unknown")
UNNUMBERED_SOLD_KEY = "tickets:unnumbered:sold"
UNNUMBERED_REQUESTS_KEY = "tickets:unnumbered:requests"
NUMBERED_SEATS_KEY = "tickets:numbered:seats"
NUMBERED_REQUESTS_KEY = "tickets:numbered:requests"

app = FastAPI(title="Ticket System Direct REST", version="0.2.0")
redis_client = Redis.from_url(REDIS_URL, decode_responses=True)

# Atomic flow:
# 1) Reject duplicate request_id
# 2) Reject when sold reaches TOTAL_TICKETS
# 3) Increment sold and persist request result
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


class BuyStatus(str, Enum):
    SUCCESS = "SUCCESS"
    SOLD_OUT = "SOLD_OUT"
    DUPLICATE = "DUPLICATE"
    SEAT_TAKEN = "SEAT_TAKEN"


class UnnumberedBuyRequest(BaseModel):
    client_id: str = Field(min_length=1)
    request_id: str = Field(min_length=1)


class UnnumberedBuyResponse(BaseModel):
    status: BuyStatus
    sold_count: int
    total_tickets: int


class NumberedBuyRequest(BaseModel):
    client_id: str = Field(min_length=1)
    seat_id: int = Field(ge=1, le=TOTAL_TICKETS)
    request_id: str = Field(min_length=1)


class NumberedBuyResponse(BaseModel):
    status: BuyStatus
    seat_id: int


@app.on_event("startup")
def startup() -> None:
    redis_client.ping()


@app.get("/health")
def health() -> dict:
    redis_ok = True
    try:
        redis_client.ping()
    except Exception:
        redis_ok = False

    return {
        "status": "ok" if redis_ok else "degraded",
        "service": "direct-rest-worker",
        "phase": "part-3-numbered",
        "worker_id": WORKER_ID,
        "redis": "ok" if redis_ok else "unreachable",
    }


@app.get("/debug/worker")
def debug_worker() -> dict:
    return {"worker_id": WORKER_ID}


@app.post("/buy/unnumbered", response_model=UnnumberedBuyResponse)
def buy_unnumbered(payload: UnnumberedBuyRequest) -> UnnumberedBuyResponse:
    result = redis_client.eval(
        UNNUMBERED_BUY_LUA,
        2,
        UNNUMBERED_SOLD_KEY,
        UNNUMBERED_REQUESTS_KEY,
        payload.request_id,
        TOTAL_TICKETS,
    )

    status = BuyStatus(result[0])
    sold_count = int(result[1])

    return UnnumberedBuyResponse(
        status=status,
        sold_count=sold_count,
        total_tickets=TOTAL_TICKETS,
    )


@app.post("/buy/numbered", response_model=NumberedBuyResponse)
def buy_numbered(payload: NumberedBuyRequest) -> NumberedBuyResponse:
    result = redis_client.eval(
        NUMBERED_BUY_LUA,
        2,
        NUMBERED_SEATS_KEY,
        NUMBERED_REQUESTS_KEY,
        payload.request_id,
        payload.seat_id,
        payload.client_id,
    )

    status = BuyStatus(result[0])
    seat_id = int(result[1])

    return NumberedBuyResponse(status=status, seat_id=seat_id)


@app.post("/admin/reset/unnumbered")
def reset_unnumbered_state() -> dict:
    redis_client.delete(UNNUMBERED_SOLD_KEY)
    redis_client.delete(UNNUMBERED_REQUESTS_KEY)
    return {"status": "ok", "message": "unnumbered state reset"}


@app.post("/admin/reset/numbered")
def reset_numbered_state() -> dict:
    redis_client.delete(NUMBERED_SEATS_KEY)
    redis_client.delete(NUMBERED_REQUESTS_KEY)
    return {"status": "ok", "message": "numbered state reset"}
