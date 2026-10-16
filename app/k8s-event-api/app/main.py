import os
import socket
from datetime import datetime
from typing import Optional

import psycopg2
from psycopg2.extras import RealDictCursor
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field


APP_NAME = os.getenv("APP_NAME", "k8s-event-api")
APP_ENV = os.getenv("APP_ENV", "local")
APP_VERSION = os.getenv("APP_VERSION", "1.0.0")

DB_HOST = os.getenv("DB_HOST", "postgres-service")
DB_PORT = int(os.getenv("DB_PORT", "5432"))
DB_NAME = os.getenv("DB_NAME", "events_db")
DB_USER = os.getenv("DB_USER", "events_user")
DB_PASSWORD = os.getenv("DB_PASSWORD", "events_password")

HOSTNAME = socket.gethostname()

app = FastAPI(
    title=APP_NAME,
    version=APP_VERSION,
)


class EventCreate(BaseModel):
    source: str = Field(..., examples=["mobile-app", "web-app", "batch-job"])
    event_type: str = Field(..., examples=["login", "purchase", "page_view"])
    payload: Optional[str] = Field(default=None, examples=['{"user_id": 123}'])


class EventResponse(BaseModel):
    id: int
    source: str
    event_type: str
    payload: Optional[str]
    created_at: datetime


def get_connection():
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=3,
    )


def init_db():
    create_table_sql = """
    CREATE TABLE IF NOT EXISTS events (
        id SERIAL PRIMARY KEY,
        source VARCHAR(100) NOT NULL,
        event_type VARCHAR(100) NOT NULL,
        payload TEXT,
        created_at TIMESTAMP NOT NULL DEFAULT NOW()
    );
    """

    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(create_table_sql)
        conn.commit()
    finally:
        conn.close()


@app.on_event("startup")
def startup():
    try:
        init_db()
        print("Database initialization completed.")
    except Exception as exc:
        print(f"Database initialization failed: {exc}")


@app.get("/")
def root():
    return {
        "message": "Kubernetes Event API is running",
        "app_name": APP_NAME,
        "environment": APP_ENV,
        "version": APP_VERSION,
        "pod": HOSTNAME,
    }


@app.get("/health")
def health():
    return {
        "status": "ok",
        "pod": HOSTNAME,
    }


@app.get("/ready")
def ready():
    try:
        conn = get_connection()
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT 1;")
                result = cur.fetchone()
        finally:
            conn.close()

        return {
            "status": "ready",
            "db_check": result[0],
            "db_host": DB_HOST,
            "pod": HOSTNAME,
        }

    except Exception as exc:
        raise HTTPException(
            status_code=503,
            detail={
                "status": "not_ready",
                "reason": str(exc),
                "db_host": DB_HOST,
                "pod": HOSTNAME,
            },
        )


@app.get("/info")
def info():
    return {
        "app_name": APP_NAME,
        "environment": APP_ENV,
        "version": APP_VERSION,
        "pod": HOSTNAME,
        "db_host": DB_HOST,
        "db_port": DB_PORT,
        "db_name": DB_NAME,
        "db_user": DB_USER,
    }


@app.post("/events", response_model=EventResponse)
def create_event(event: EventCreate):
    insert_sql = """
    INSERT INTO events (source, event_type, payload)
    VALUES (%s, %s, %s)
    RETURNING id, source, event_type, payload, created_at;
    """

    try:
        conn = get_connection()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(
                    insert_sql,
                    (event.source, event.event_type, event.payload),
                )
                row = cur.fetchone()
            conn.commit()
            return row
        finally:
            conn.close()

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail={
                "message": "Failed to create event",
                "reason": str(exc),
                "pod": HOSTNAME,
            },
        )


@app.get("/events")
def list_events(limit: int = 20):
    limit = min(limit, 100)

    select_sql = """
    SELECT id, source, event_type, payload, created_at
    FROM events
    ORDER BY id DESC
    LIMIT %s;
    """

    try:
        conn = get_connection()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(select_sql, (limit,))
                rows = cur.fetchall()

            return {
                "count": len(rows),
                "events": rows,
                "pod": HOSTNAME,
            }
        finally:
            conn.close()

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail={
                "message": "Failed to list events",
                "reason": str(exc),
                "pod": HOSTNAME,
            },
        )


@app.get("/stats")
def stats():
    stats_sql = """
    SELECT
        COUNT(*) AS total_events,
        COUNT(DISTINCT source) AS distinct_sources,
        COUNT(DISTINCT event_type) AS distinct_event_types
    FROM events;
    """

    try:
        conn = get_connection()
        try:
            with conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(stats_sql)
                row = cur.fetchone()

            return {
                "stats": row,
                "pod": HOSTNAME,
            }
        finally:
            conn.close()

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail={
                "message": "Failed to get stats",
                "reason": str(exc),
                "pod": HOSTNAME,
            },
        )