from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import mysql.connector, os

app = FastAPI()

DB = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", 3306)),
    "user": os.getenv("MYSQL_USER", "test_user"),
    "password": os.getenv("MYSQL_PASSWORD", "test_pass"),
    "database": os.getenv("MYSQL_DATABASE", "test_db"),
    "autocommit": True,
}

class Item(BaseModel):
    name: str
    description: str | None = None

def conn():
    return mysql.connector.connect(**DB)

@app.post("/items", status_code=201)
def create_item(it: Item):
    with conn() as c, c.cursor() as cur:
        cur.execute(
            "INSERT INTO items (name, description) VALUES (%s,%s)",
            (it.name, it.description),
        )
        return {"id": cur.lastrowid, **it.dict()}

@app.get("/items")
def list_items():
    with conn() as c, c.cursor(dictionary=True) as cur:
        cur.execute("SELECT * FROM items ORDER BY id DESC")
        return cur.fetchall()

@app.put("/items/{item_id}", status_code=200)
def update_item(item_id: int, it: Item):
    with conn() as c, c.cursor() as cur:
        # Check if item exists
        cur.execute("SELECT id FROM items WHERE id = %s", (item_id,))
        if not cur.fetchone():
            raise HTTPException(status_code=404, detail="Item not found")
            
        # Update the item
        cur.execute(
            "UPDATE items SET name = %s, description = %s WHERE id = %s",
            (it.name, it.description, item_id)
        )
        return {"id": item_id, **it.dict()}
