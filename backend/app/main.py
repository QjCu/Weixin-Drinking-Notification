"""Two-person notes API. Run one worker; SQLite is sufficient for a small pilot."""
from collections import defaultdict, deque
from contextlib import asynccontextmanager
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import secrets
import sqlite3
from threading import Lock
import time
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field, field_validator


class NameInput(BaseModel):
    name: str = Field(min_length=1, max_length=24)

    @field_validator("name")
    @classmethod
    def strip_name(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("请输入昵称")
        return value.strip()


class BindInput(BaseModel):
    invite_code: str = Field(min_length=12, max_length=12)

    @field_validator("invite_code")
    @classmethod
    def normalize_code(cls, value: str) -> str:
        return value.upper()


class NoteInput(BaseModel):
    text: str = Field(min_length=1, max_length=140)
    client_id: str = Field(min_length=1, max_length=64)

    @field_validator("text")
    @classmethod
    def strip_text(cls, value: str) -> str:
        if not value.strip():
            raise ValueError("留言不能为空")
        return value.strip()


class AckInput(BaseModel):
    ids: list[str] = Field(max_length=100)


SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
 id TEXT PRIMARY KEY, name TEXT NOT NULL, token_hash TEXT UNIQUE NOT NULL,
 invite_code TEXT UNIQUE NOT NULL, partner_id TEXT REFERENCES users(id)
);
CREATE TABLE IF NOT EXISTS notes (
 id TEXT PRIMARY KEY, sender_id TEXT NOT NULL REFERENCES users(id),
 recipient_id TEXT NOT NULL REFERENCES users(id), text TEXT NOT NULL,
 client_id TEXT NOT NULL, created_at TEXT NOT NULL, acknowledged INTEGER NOT NULL DEFAULT 0,
 UNIQUE(sender_id, client_id)
);
CREATE INDEX IF NOT EXISTS inbox ON notes(recipient_id, acknowledged, created_at);
"""


def create_app(database: str | Path | None = None) -> FastAPI:
    path = Path(database or os.environ.get("SIPTIME_DB", "data/siptime.sqlite3"))

    def connect():
        db = sqlite3.connect(path, timeout=10, check_same_thread=False)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        return db

    @asynccontextmanager
    async def lifespan(app):
        path.parent.mkdir(parents=True, exist_ok=True)
        with connect() as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.executescript(SCHEMA)
        yield

    api = FastAPI(title="课间一口 · SipTime", version="0.1.0", lifespan=lifespan)
    security = HTTPBearer(auto_error=False)
    attempts: dict[tuple[str, str], deque[float]] = defaultdict(deque)
    limiter_lock = Lock()

    def limit(key: tuple[str, str], maximum: int, seconds: int = 60):
        now = time.monotonic()
        with limiter_lock:
            # Purge expired buckets so random IPs cannot grow the map indefinitely.
            for old in list(attempts):
                if not attempts[old] or attempts[old][-1] <= now - 3600:
                    del attempts[old]
            bucket = attempts[key]
            while bucket and bucket[0] <= now - seconds:
                bucket.popleft()
            if len(bucket) >= maximum:
                raise HTTPException(429, "操作太频繁，请稍后再试", headers={"Retry-After": str(seconds)})
            bucket.append(now)

    def connection():
        db = connect()
        try:
            # Serialize read-modify-write operations, including mutual pairing.
            db.execute("BEGIN IMMEDIATE")
            yield db
            db.commit()
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()

    DB = Annotated[sqlite3.Connection, Depends(connection)]

    def authenticated(
        db: DB,
        credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(security)],
    ):
        if credentials is None:
            raise HTTPException(401, "请先注册", headers={"WWW-Authenticate": "Bearer"})
        digest = hashlib.sha256(credentials.credentials.encode()).hexdigest()
        user = db.execute("SELECT * FROM users WHERE token_hash=?", (digest,)).fetchone()
        if user is None:
            raise HTTPException(401, "凭据无效", headers={"WWW-Authenticate": "Bearer"})
        return user

    User = Annotated[sqlite3.Row, Depends(authenticated)]

    @api.middleware("http")
    async def private_responses(request: Request, call_next):
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response

    def profile(db, user):
        peer = db.execute("SELECT id, name FROM users WHERE id=?", (user["partner_id"],)).fetchone()
        return {"id": user["id"], "name": user["name"], "invite_code": user["invite_code"],
                "peer_name": peer["name"] if peer else None}

    @api.get("/health")
    def health():
        return {"status": "ok"}

    @api.post("/v1/accounts", status_code=201)
    def register(body: NameInput, request: Request, db: DB):
        limit(("register", request.client.host if request.client else "unknown"), 10, 3600)
        token = secrets.token_urlsafe(32)
        user_id = secrets.token_hex(16)
        db.execute("INSERT INTO users(id,name,token_hash,invite_code) VALUES(?,?,?,?)",
                   (user_id, body.name, hashlib.sha256(token.encode()).hexdigest(), secrets.token_hex(6).upper()))
        return {"token": token}

    @api.get("/v1/me")
    def me(user: User, db: DB):
        return profile(db, user)

    @api.post("/v1/pair")
    def pair(body: BindInput, user: User, db: DB):
        limit(("pair", user["id"]), 10)
        peer = db.execute("SELECT * FROM users WHERE invite_code=?", (body.invite_code,)).fetchone()
        if peer is None or peer["id"] == user["id"]:
            raise HTTPException(400, "邀请码不可用")
        if user["partner_id"] == peer["id"] and peer["partner_id"] == user["id"]:
            return profile(db, user)
        if user["partner_id"] or peer["partner_id"]:
            raise HTTPException(409, "其中一方已绑定好友，请先解除绑定")
        db.execute("UPDATE users SET partner_id=? WHERE id=?", (peer["id"], user["id"]))
        db.execute("UPDATE users SET partner_id=? WHERE id=?", (user["id"], peer["id"]))
        return profile(db, db.execute("SELECT * FROM users WHERE id=?", (user["id"],)).fetchone())

    @api.delete("/v1/pair", status_code=204)
    def unpair(user: User, db: DB):
        if user["partner_id"]:
            db.execute("DELETE FROM notes WHERE (sender_id=? AND recipient_id=?) OR (sender_id=? AND recipient_id=?)",
                       (user["id"], user["partner_id"], user["partner_id"], user["id"]))
            db.execute("UPDATE users SET partner_id=NULL WHERE id IN (?,?)", (user["id"], user["partner_id"]))
        return Response(status_code=204)

    @api.post("/v1/notes", status_code=201)
    def send_note(body: NoteInput, user: User, db: DB):
        limit(("send", user["id"]), 20)
        if not user["partner_id"]:
            raise HTTPException(409, "请先绑定好友")
        previous = db.execute("SELECT * FROM notes WHERE sender_id=? AND client_id=?",
                              (user["id"], body.client_id)).fetchone()
        if previous:
            if previous["text"] != body.text:
                raise HTTPException(409, "此请求编号已经用于其他留言")
            return {"id": previous["id"]}
        count = db.execute("SELECT COUNT(*) FROM notes WHERE sender_id=? AND acknowledged=0", (user["id"],)).fetchone()[0]
        if count >= 20:
            raise HTTPException(409, "待提醒留言已满，请等待对方同步并提醒后再发送")
        note_id = secrets.token_hex(16)
        db.execute("INSERT INTO notes(id,sender_id,recipient_id,text,client_id,created_at) VALUES(?,?,?,?,?,?)",
                   (note_id, user["id"], user["partner_id"], body.text, body.client_id,
                    datetime.now(timezone.utc).isoformat(timespec="seconds")))
        return {"id": note_id}

    @api.get("/v1/notes/inbox")
    def inbox(user: User, db: DB):
        rows = db.execute("SELECT n.id,n.text,u.name AS sender_name,n.created_at FROM notes n JOIN users u "
                          "ON u.id=n.sender_id WHERE recipient_id=? AND acknowledged=0 ORDER BY n.rowid LIMIT 20",
                          (user["id"],)).fetchall()
        return [dict(row) for row in rows]

    @api.post("/v1/notes/ack", status_code=204)
    def acknowledge(body: AckInput, user: User, db: DB):
        # Only the recipient can acknowledge a note; repeated acknowledgements are safe.
        db.executemany("UPDATE notes SET acknowledged=1 WHERE id=? AND recipient_id=?",
                       [(note_id, user["id"]) for note_id in body.ids])
        return Response(status_code=204)

    return api


app = create_app()
