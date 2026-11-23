"""Consume integration events and update an idempotent local projection."""

import json
import os
import sqlite3
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path

from kafka import KafkaConsumer
from kafka.structs import OffsetAndMetadata, TopicPartition


DATABASE_PATH = Path(os.getenv("SQLITE_PATH", "./o09-events.db"))
TOPIC = os.getenv("KAFKA_TOPIC", "integration-events")
GROUP_ID = os.getenv("KAFKA_GROUP_ID", "order-projection-v1")


def kafka_config() -> dict[str, object]:
    """Return Kafka client settings without storing credentials in source."""
    required = (
        "KAFKA_BOOTSTRAP_SERVERS",
        "KAFKA_SASL_USERNAME",
        "KAFKA_SASL_PASSWORD",
    )
    missing = [key for key in required if not os.getenv(key)]
    if missing:
        raise RuntimeError(f"Missing environment variables: {', '.join(missing)}")

    return {
        "bootstrap_servers": os.environ["KAFKA_BOOTSTRAP_SERVERS"].split(","),
        "security_protocol": "SASL_SSL",
        "sasl_mechanism": "PLAIN",
        "sasl_plain_username": os.environ["KAFKA_SASL_USERNAME"],
        "sasl_plain_password": os.environ["KAFKA_SASL_PASSWORD"],
        "key_deserializer": lambda value: value.decode("utf-8"),
        "value_deserializer": lambda value: json.loads(value.decode("utf-8")),
        "group_id": GROUP_ID,
        "enable_auto_commit": False,
        "auto_offset_reset": "earliest",
    }


def connect_database() -> sqlite3.Connection:
    connection = sqlite3.connect(DATABASE_PATH)
    connection.row_factory = sqlite3.Row
    return connection


def initialize_database(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        CREATE TABLE IF NOT EXISTS processed_events (
            event_id TEXT PRIMARY KEY,
            processed_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS order_projection (
            order_id TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            last_event_id TEXT NOT NULL
        );
        """
    )
    connection.commit()


def apply_event(connection: sqlite3.Connection, event: dict[str, object]) -> bool:
    """Transactionally deduplicate and apply an OrderCreated event.

    Return True when applied; return False when this event was already processed.
    """
    if not isinstance(event, dict):
        raise ValueError("Event must be a JSON object")

    event_id = event.get("event_id")
    event_type = event.get("event_type")
    aggregate_id = event.get("aggregate_id")
    payload = event.get("payload")

    if not all(
        isinstance(value, str) and value
        for value in (event_id, event_type, aggregate_id)
    ):
        raise ValueError(
            "Event must include non-empty event_id, event_type, and aggregate_id"
        )
    if event_type != "OrderCreated":
        raise ValueError(f"Unsupported event_type: {event_type}")
    if not isinstance(payload, dict):
        raise ValueError("Event payload must be an object")

    order_id = payload.get("order_id")
    status = payload.get("status")
    if order_id != aggregate_id or not isinstance(status, str) or not status:
        raise ValueError(
            "OrderCreated payload must match aggregate_id and include status"
        )

    processed_at = datetime.now(timezone.utc).isoformat()
    with connection:
        result = connection.execute(
            """
            INSERT OR IGNORE INTO processed_events (event_id, processed_at)
            VALUES (?, ?)
            """,
            (event_id, processed_at),
        )
        if result.rowcount == 0:
            return False

        connection.execute(
            """
            INSERT INTO order_projection (order_id, status, last_event_id)
            VALUES (?, ?, ?)
            ON CONFLICT(order_id) DO UPDATE SET
                status = excluded.status,
                last_event_id = excluded.last_event_id
            """,
            (order_id, status, event_id),
        )

    return True


def main() -> None:
    consumer = KafkaConsumer(TOPIC, **kafka_config())
    try:
        with closing(connect_database()) as connection:
            initialize_database(connection)
            print(f"Listening on {TOPIC!r} as group {GROUP_ID!r}; Ctrl-C to stop.")
            for message in consumer:
                event = message.value
                applied = apply_event(connection, event)
                # Commit only this record's next offset, after the SQLite
                # transaction commits; don't advance past unprocessed records.
                consumer.commit(
                    {
                        TopicPartition(
                            message.topic, message.partition
                        ): OffsetAndMetadata(message.offset + 1, "")
                    }
                )
                result = "applied" if applied else "duplicate ignored"
                print(f"{event['event_id']}: {result}")
    finally:
        consumer.close()


if __name__ == "__main__":
    main()
