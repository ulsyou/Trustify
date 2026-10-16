import os

import psycopg2
from fastapi import FastAPI

app = FastAPI()


def get_db_connection():
    conn = psycopg2.connect(
        host=os.getenv("DB_HOST", "db"),
        port=os.getenv("DB_PORT", "5432"),
        database=os.getenv("DB_NAME", "demo_db"),
        user=os.getenv("DB_USER", "ekrem"),
        password=os.getenv("DB_PASSWORD", "ekrem6161"),
    )
    return conn


@app.get("/")
def root():
    return {
        "message": "FastAPI is running"
    }


@app.get("/health")
def health():
    return {
        "status": "ok"
    }


@app.get("/db-check")
def db_check():
    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("SELECT 1;")
    result = cursor.fetchone()

    cursor.close()
    conn.close()

    return {
        "db_status": "ok",
        "result": result[0]
    }