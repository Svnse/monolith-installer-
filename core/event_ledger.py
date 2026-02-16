"""Event ledger facade over OverseerDB.

This module is intentionally UI-agnostic and safe to call from hot signal paths.
"""

from __future__ import annotations

from dataclasses import asdict, is_dataclass
from datetime import date, datetime, timezone
from enum import Enum
import base64
import json
import queue
import threading
import time
from pathlib import Path
from typing import Any
from uuid import uuid4


class EventLedger:
    """Non-blocking event facade with background batched persistence.

    The ledger wraps an OverseerDB-like adapter that provides DB cursor/commit
    operations and is responsible for schema migration and durable write policy.
    """

    FLUSH_INTERVAL_S = 0.1
    MAX_BATCH_SIZE = 50

    def __init__(self, db: Any, app_version: str = "") -> None:
        self._db = db
        self._app_version = app_version
        self._session_id = str(uuid4())
        self._seq = 0
        self._seq_lock = threading.Lock()
        self._queue: queue.Queue[dict[str, Any]] = queue.Queue()
        self._stop_event = threading.Event()
        self._worker = threading.Thread(target=self._writer_loop, name="event-ledger-writer", daemon=True)

        self._ensure_schema()
        self._worker.start()
        self.record(
            "core.ledger",
            "lifecycle",
            "session_start",
            payload={"app_version": self._app_version},
            severity=1,
        )

    @property
    def session_id(self) -> str:
        return self._session_id

    def shutdown(self) -> None:
        """Flush and stop writer thread; records session end exactly once."""
        if self._stop_event.is_set():
            return
        self.record("core.ledger", "lifecycle", "session_end", payload={"app_version": self._app_version}, severity=1)
        self._stop_event.set()
        self._worker.join(timeout=2.0)
        self._flush_pending(force=True)

    def ingest(
        self,
        *,
        source: str,
        kind: str,
        name: str,
        payload: Any | None = None,
        engine_key: str = "",
        severity: int = 1,
        correlation_id: str | None = None,
        parent_id: int | None = None,
        timestamp: datetime | None = None,
    ) -> None:
        """Queue an event without blocking caller.

        Serialization is defensive and never raises to callers.
        """
        try:
            serialized_payload = self._safe_payload(payload)
        except Exception:
            serialized_payload = {"_error": "serialization_failed"}

        with self._seq_lock:
            self._seq += 1
            seq = self._seq

        event = {
            "ts": (timestamp or datetime.now(timezone.utc)).isoformat(),
            "event": name,
            "engine_key": engine_key,
            "payload": json.dumps(serialized_payload, ensure_ascii=False),
            "session_id": self._session_id,
            "seq": seq,
            "source": source,
            "kind": kind,
            "severity": int(severity),
            "correlation_id": correlation_id,
            "parent_id": parent_id,
        }

        try:
            self._queue.put_nowait(event)
        except queue.Full:
            # Backpressure guard: drop newest if queue is saturated.
            pass

    def record(
        self,
        source: str,
        kind: str,
        name: str,
        payload: Any | None = None,
        engine_key: str = "",
        severity: int = 1,
        correlation_id: str | None = None,
        parent_id: int | None = None,
    ) -> None:
        """Convenience alias for ingest()."""
        self.ingest(
            source=source,
            kind=kind,
            name=name,
            payload=payload,
            engine_key=engine_key,
            severity=severity,
            correlation_id=correlation_id,
            parent_id=parent_id,
        )

    def _writer_loop(self) -> None:
        last_flush = time.monotonic()
        batch: list[dict[str, Any]] = []

        while not self._stop_event.is_set():
            timeout = max(0.0, self.FLUSH_INTERVAL_S - (time.monotonic() - last_flush))
            try:
                item = self._queue.get(timeout=timeout)
                batch.append(item)
                if len(batch) >= self.MAX_BATCH_SIZE:
                    self._write_batch(batch)
                    batch.clear()
                    last_flush = time.monotonic()
            except queue.Empty:
                if batch:
                    self._write_batch(batch)
                    batch.clear()
                last_flush = time.monotonic()

        # drain remaining events
        while True:
            try:
                batch.append(self._queue.get_nowait())
                if len(batch) >= self.MAX_BATCH_SIZE:
                    self._write_batch(batch)
                    batch.clear()
            except queue.Empty:
                break
        if batch:
            self._write_batch(batch)

    def _flush_pending(self, force: bool = False) -> None:
        if not force:
            return
        batch: list[dict[str, Any]] = []
        while True:
            try:
                batch.append(self._queue.get_nowait())
            except queue.Empty:
                break
        if batch:
            self._write_batch(batch)

    def _ensure_schema(self) -> None:
        cols = [
            ("session_id", "TEXT DEFAULT ''"),
            ("seq", "INTEGER DEFAULT 0"),
            ("source", "TEXT DEFAULT ''"),
            ("kind", "TEXT DEFAULT ''"),
            ("severity", "INTEGER DEFAULT 1"),
            ("correlation_id", "TEXT"),
            ("parent_id", "INTEGER"),
        ]

        conn = getattr(self._db, "conn", None)
        if conn is None:
            return

        cur = conn.cursor()
        for col_name, col_def in cols:
            try:
                cur.execute(f"ALTER TABLE events ADD COLUMN {col_name} {col_def}")
            except Exception:
                # Column likely already exists; intentionally ignored.
                continue
        conn.commit()

    def _write_batch(self, batch: list[dict[str, Any]]) -> None:
        conn = getattr(self._db, "conn", None)
        if conn is None:
            return

        cur = conn.cursor()
        cur.executemany(
            """
            INSERT INTO events(
                ts, event, engine_key, payload, session_id, seq, source, kind, severity, correlation_id, parent_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                (
                    item["ts"],
                    item["event"],
                    item["engine_key"],
                    item["payload"],
                    item["session_id"],
                    item["seq"],
                    item["source"],
                    item["kind"],
                    item["severity"],
                    item["correlation_id"],
                    item["parent_id"],
                )
                for item in batch
            ],
        )
        conn.commit()

    def _safe_payload(self, payload: Any) -> Any:
        if payload is None:
            return {}
        return self._serialize(payload)

    def _serialize(self, value: Any) -> Any:
        if isinstance(value, (str, int, float, bool)) or value is None:
            return value
        if isinstance(value, Enum):
            return value.value
        if isinstance(value, Path):
            return str(value)
        if isinstance(value, (datetime, date)):
            return value.isoformat()
        if is_dataclass(value):
            return {k: self._serialize(v) for k, v in asdict(value).items()}
        if isinstance(value, bytes):
            return {"_type": "bytes", "base64": base64.b64encode(value).decode("ascii")}
        if isinstance(value, dict):
            return {str(k): self._serialize(v) for k, v in value.items()}
        if isinstance(value, (list, tuple, set)):
            return [self._serialize(v) for v in value]
        if hasattr(value, "save") and value.__class__.__name__ == "QImage":
            # Avoid Qt import hard dependency; represent image payload safely.
            return {"_type": "QImage", "repr": repr(value)}
        if hasattr(value, "__dict__"):
            return {k: self._serialize(v) for k, v in vars(value).items() if not k.startswith("_")}
        return str(value)
