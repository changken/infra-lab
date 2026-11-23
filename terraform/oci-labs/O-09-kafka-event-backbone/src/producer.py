"""Create an order and relay its outbox event to OCI Streaming."""

import json
import os
import sqlite3
import uuid
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path

from kafka import KafkaProducer


DATABASE_PATH = Path(os.getenv("SQLITE_PATH", "./o09-events.db"))
TOPIC = os.getenv("KAFKA_TOPIC", "integration-events")


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
        "key_serializer": lambda value: value.encode("utf-8"),
        "value_serializer": lambda value: json.dumps(value).encode("utf-8"),
        "acks": "all",
    }


def connect_database() -> sqlite3.Connection:
    connection = sqlite3.connect(DATABASE_PATH)
    connection.row_factory = sqlite3.Row
    return connection


def initialize_database(connection: sqlite3.Connection) -> None:
    connection.executescript(
        """
        CREATE TABLE IF NOT EXISTS orders (
            order_id TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            created_at TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS outbox (
            event_id TEXT PRIMARY KEY,
            aggregate_id TEXT NOT NULL,
            event_type TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at TEXT NOT NULL,
            published_at TEXT
        );
        """
    )
    connection.commit()


def create_order_and_outbox_event(connection: sqlite3.Connection) -> str:
    """Atomically insert an order and its integration event."""
    order_id = str(uuid.uuid4())
    event_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).isoformat()
    event = {
        "event_id": event_id,
        "event_type": "OrderCreated",
        "schema_version": 1,
        "occurred_at": now,
        "aggregate_id": order_id,
        "payload": {"order_id": order_id, "status": "created"},
    }

    with connection:
        connection.execute(
            """
            INSERT INTO orders (order_id, status, created_at)
            VALUES (?, ?, ?)
            """,
            (order_id, "created", now),
        )
        connection.execute(
            """
            INSERT INTO outbox (
                event_id, aggregate_id, event_type, payload, created_at
            )
            VALUES (?, ?, ?, ?, ?)
            """,
            (event_id, order_id, event["event_type"], json.dumps(event), now),
        )

    return order_id


def publish_pending_events(
    connection: sqlite3.Connection, producer: KafkaProducer
) -> int:
    """Publish pending rows, then mark them published after broker ACK."""
    rows = connection.execute(
        """
        SELECT event_id, aggregate_id, payload
        FROM outbox
        WHERE published_at IS NULL
        ORDER BY created_at, event_id
        LIMIT 100
        """
    ).fetchall()

    published_count = 0
    for row in rows:
        event = json.loads(row["payload"])

        # Use the aggregate ID as key so events for one order stay on one partition.
        # Waiting for the broker ACK before marking the row avoids losing events.
        # A crash between these two operations can still result in a duplicate.
        producer.send(
            TOPIC,
            key=row["aggregate_id"],
            value=event,
        ).get(timeout=30)

        published_at = datetime.now(timezone.utc).isoformat()
        with connection:
            result = connection.execute(
                """
                UPDATE outbox
                SET published_at = ?
                WHERE event_id = ? AND published_at IS NULL
                """,
                (published_at, row["event_id"]),
            )
        published_count += result.rowcount

    return published_count


def main() -> None:
    with closing(connect_database()) as connection:
        initialize_database(connection)
        order_id = create_order_and_outbox_event(connection)

        producer = KafkaProducer(**kafka_config())
        try:
            count = publish_pending_events(connection, producer)
            print(f"Created order {order_id}; published {count} outbox event(s).")
        finally:
            producer.flush()
            producer.close()


if __name__ == "__main__":
    main()
