"""FastAPI application exposing CRUD operations for items."""

from __future__ import annotations

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from .db import get_connection

app = FastAPI()


class Item(BaseModel):
    """Simple item representation stored in MySQL."""

    name: str = Field(..., min_length=1)
    description: str | None = None


@app.post("/items", status_code=201)
def create_item(item: Item):
    """Create a new item and return the persisted representation."""

    with get_connection() as (_, cursor):
        cursor.execute(
            "INSERT INTO items (name, description) VALUES (%s,%s)",
            (item.name, item.description),
        )
        item_id = cursor.lastrowid

    return {"id": item_id, **item.dict()}


@app.get("/items")
def list_items():
    """Return all items ordered by creation (descending)."""

    with get_connection(dictionary=True) as (_, cursor):
        cursor.execute("SELECT * FROM items ORDER BY id DESC")
        return cursor.fetchall()


@app.put("/items/{item_id}", status_code=200)
def update_item(item_id: int, item: Item):
    """Update the stored item if it exists, otherwise raise 404."""

    with get_connection() as (_, cursor):
        cursor.execute("SELECT id FROM items WHERE id = %s", (item_id,))
        if not cursor.fetchone():
            raise HTTPException(status_code=404, detail="Item not found")

        cursor.execute(
            "UPDATE items SET name = %s, description = %s WHERE id = %s",
            (item.name, item.description, item_id),
        )

    return {"id": item_id, **item.dict()}
