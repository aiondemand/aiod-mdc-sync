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


class User(BaseModel):
    """User representation stored in MySQL."""

    username: str = Field(..., min_length=1, max_length=100)
    email: str = Field(..., min_length=1, max_length=255)


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


@app.delete("/items/{item_id}", status_code=204)
def delete_item(item_id: int):
    """Delete the stored item if it exists, otherwise raise 404."""

    with get_connection() as (_, cursor):
        cursor.execute("SELECT id FROM items WHERE id = %s", (item_id,))
        if not cursor.fetchone():
            raise HTTPException(status_code=404, detail="Item not found")

        cursor.execute("DELETE FROM items WHERE id = %s", (item_id,))

    return None


# ============================================================================
# User CRUD operations
# ============================================================================


@app.post("/users", status_code=201)
def create_user(user: User):
    """Create a new user and return the persisted representation."""

    with get_connection() as (_, cursor):
        try:
            cursor.execute(
                "INSERT INTO users (username, email) VALUES (%s, %s)",
                (user.username, user.email),
            )
            user_id = cursor.lastrowid
        except Exception as e:
            if "Duplicate entry" in str(e):
                raise HTTPException(status_code=400, detail="Username already exists")
            raise

    return {"id": user_id, **user.dict()}


@app.get("/users")
def list_users():
    """Return all users ordered by creation (descending)."""

    with get_connection(dictionary=True) as (_, cursor):
        cursor.execute("SELECT * FROM users ORDER BY id DESC")
        return cursor.fetchall()


@app.get("/users/{user_id}")
def get_user(user_id: int):
    """Get a specific user by ID."""

    with get_connection(dictionary=True) as (_, cursor):
        cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))
        user = cursor.fetchone()
        if not user:
            raise HTTPException(status_code=404, detail="User not found")
        return user


@app.put("/users/{user_id}", status_code=200)
def update_user(user_id: int, user: User):
    """Update the stored user if it exists, otherwise raise 404."""

    with get_connection() as (_, cursor):
        cursor.execute("SELECT id FROM users WHERE id = %s", (user_id,))
        if not cursor.fetchone():
            raise HTTPException(status_code=404, detail="User not found")

        try:
            cursor.execute(
                "UPDATE users SET username = %s, email = %s WHERE id = %s",
                (user.username, user.email, user_id),
            )
        except Exception as e:
            if "Duplicate entry" in str(e):
                raise HTTPException(status_code=400, detail="Username already exists")
            raise

    return {"id": user_id, **user.dict()}


@app.delete("/users/{user_id}", status_code=204)
def delete_user(user_id: int):
    """Delete the stored user if it exists, otherwise raise 404."""

    with get_connection() as (_, cursor):
        cursor.execute("SELECT id FROM users WHERE id = %s", (user_id,))
        if not cursor.fetchone():
            raise HTTPException(status_code=404, detail="User not found")

        cursor.execute("DELETE FROM users WHERE id = %s", (user_id,))

    return None


# ============================================================================
# DDL operations (Schema management)
# ============================================================================


class AddColumnRequest(BaseModel):
    """Request to add a column to a table."""

    table_name: str = Field(..., min_length=1)
    column_name: str = Field(..., min_length=1)
    column_type: str = Field(..., min_length=1)
    default_value: str | None = None
    nullable: bool = True


class RemoveColumnRequest(BaseModel):
    """Request to remove a column from a table."""

    table_name: str = Field(..., min_length=1)
    column_name: str = Field(..., min_length=1)


class CreateTableRequest(BaseModel):
    """Request to create a new table."""

    table_name: str = Field(..., min_length=1)
    columns: dict[str, str] = Field(..., min_items=1)  # column_name: column_definition


@app.post("/admin/add-column", status_code=200)
def add_column(request: AddColumnRequest):
    """Add a new column to an existing table."""

    # Basic SQL injection prevention - only allow alphanumeric and underscore
    import re
    if not re.match(r'^[a-zA-Z0-9_]+$', request.table_name):
        raise HTTPException(status_code=400, detail="Invalid table name")
    if not re.match(r'^[a-zA-Z0-9_]+$', request.column_name):
        raise HTTPException(status_code=400, detail="Invalid column name")

    # Build ALTER TABLE query
    null_clause = "NULL" if request.nullable else "NOT NULL"
    default_clause = f"DEFAULT {request.default_value}" if request.default_value else ""
    
    query = f"ALTER TABLE {request.table_name} ADD COLUMN {request.column_name} {request.column_type} {null_clause} {default_clause};"

    try:
        with get_connection() as (_, cursor):
            cursor.execute(query)
        return {
            "message": f"Column '{request.column_name}' added to table '{request.table_name}'",
            "query": query
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to add column: {str(e)}")


@app.post("/admin/remove-column", status_code=200)
def remove_column(request: RemoveColumnRequest):
    """Remove a column from an existing table."""

    import re
    if not re.match(r'^[a-zA-Z0-9_]+$', request.table_name):
        raise HTTPException(status_code=400, detail="Invalid table name")
    if not re.match(r'^[a-zA-Z0-9_]+$', request.column_name):
        raise HTTPException(status_code=400, detail="Invalid column name")

    query = f"ALTER TABLE {request.table_name} DROP COLUMN {request.column_name};"

    try:
        with get_connection() as (_, cursor):
            cursor.execute(query)
        return {
            "message": f"Column '{request.column_name}' removed from table '{request.table_name}'",
            "query": query
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to remove column: {str(e)}")


@app.post("/admin/create-table", status_code=201)
def create_table(request: CreateTableRequest):
    """Create a new table with specified columns."""

    import re
    if not re.match(r'^[a-zA-Z0-9_]+$', request.table_name):
        raise HTTPException(status_code=400, detail="Invalid table name")

    # Build column definitions
    column_defs = []
    for col_name, col_def in request.columns.items():
        if not re.match(r'^[a-zA-Z0-9_]+$', col_name):
            raise HTTPException(status_code=400, detail=f"Invalid column name: {col_name}")
        column_defs.append(f"{col_name} {col_def}")

    columns_str = ", ".join(column_defs)
    query = f"CREATE TABLE IF NOT EXISTS {request.table_name} ({columns_str});"

    try:
        with get_connection() as (_, cursor):
            cursor.execute(query)
        return {
            "message": f"Table '{request.table_name}' created successfully",
            "query": query
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to create table: {str(e)}")


@app.get("/admin/tables")
def list_tables():
    """Get all tables in the current database."""

    try:
        with get_connection(dictionary=True) as (_, cursor):
            cursor.execute("SHOW TABLES;")
            tables = cursor.fetchall()
            # Convert from [{'Tables_in_test_db': 'items'}, ...] to ['items', ...]
            table_names = [list(table.values())[0] for table in tables]
            return {"tables": table_names}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to list tables: {str(e)}")


@app.get("/admin/describe/{table_name}")
def describe_table(table_name: str):
    """Get the schema of a table."""

    import re
    if not re.match(r'^[a-zA-Z0-9_]+$', table_name):
        raise HTTPException(status_code=400, detail="Invalid table name")

    try:
        with get_connection(dictionary=True) as (_, cursor):
            cursor.execute(f"DESCRIBE {table_name};")
            return cursor.fetchall()
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"Table not found or error: {str(e)}")


@app.post("/table/{table_name}", status_code=201)
def insert_into_table(table_name: str, data: dict):
    """Insert a row into any table dynamically."""

    import re
    if not re.match(r'^[a-zA-Z0-9_]+$', table_name):
        raise HTTPException(status_code=400, detail="Invalid table name")
    
    if not data:
        raise HTTPException(status_code=400, detail="No data provided")

    # Validate column names
    for key in data.keys():
        if not re.match(r'^[a-zA-Z0-9_]+$', key):
            raise HTTPException(status_code=400, detail=f"Invalid column name: {key}")

    # Build INSERT query
    columns = ", ".join(data.keys())
    placeholders = ", ".join(["%s"] * len(data))
    values = tuple(data.values())

    query = f"INSERT INTO {table_name} ({columns}) VALUES ({placeholders})"

    try:
        with get_connection() as (_, cursor):
            cursor.execute(query, values)
            row_id = cursor.lastrowid
        
        return {"id": row_id, **data, "table": table_name}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to insert: {str(e)}")


@app.get("/table/{table_name}")
def get_all_from_table(table_name: str):
    """Get all rows from any table."""

    import re
    if not re.match(r'^[a-zA-Z0-9_]+$', table_name):
        raise HTTPException(status_code=400, detail="Invalid table name")

    try:
        with get_connection(dictionary=True) as (_, cursor):
            cursor.execute(f"SELECT * FROM {table_name} ORDER BY id DESC")
            return cursor.fetchall()
    except Exception as e:
        raise HTTPException(status_code=404, detail=f"Table not found or error: {str(e)}")


@app.get("/table/{table_name}/{row_id}")
def get_row_from_table(table_name: str, row_id: int):
    """Get a specific row from any table by ID."""

    import re
    if not re.match(r'^[a-zA-Z0-9_]+$', table_name):
        raise HTTPException(status_code=400, detail="Invalid table name")

    try:
        with get_connection(dictionary=True) as (_, cursor):
            cursor.execute(f"SELECT * FROM {table_name} WHERE id = %s", (row_id,))
            row = cursor.fetchone()
            if not row:
                raise HTTPException(status_code=404, detail="Row not found")
            return row
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error: {str(e)}")


@app.put("/table/{table_name}/{row_id}")
def update_row_in_table(table_name: str, row_id: int, data: dict):
    """Update a row in any table by ID."""

    import re
    if not re.match(r'^[a-zA-Z0-9_]+$', table_name):
        raise HTTPException(status_code=400, detail="Invalid table name")
    
    if not data:
        raise HTTPException(status_code=400, detail="No data provided")

    # Validate column names
    for key in data.keys():
        if not re.match(r'^[a-zA-Z0-9_]+$', key):
            raise HTTPException(status_code=400, detail=f"Invalid column name: {key}")

    # Build UPDATE query
    set_clause = ", ".join([f"{key} = %s" for key in data.keys()])
    values = tuple(data.values()) + (row_id,)

    query = f"UPDATE {table_name} SET {set_clause} WHERE id = %s"

    try:
        with get_connection() as (_, cursor):
            cursor.execute(f"SELECT id FROM {table_name} WHERE id = %s", (row_id,))
            if not cursor.fetchone():
                raise HTTPException(status_code=404, detail="Row not found")
            
            cursor.execute(query, values)
        
        return {"id": row_id, **data, "table": table_name}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to update: {str(e)}")


@app.delete("/table/{table_name}/{row_id}", status_code=204)
def delete_row_from_table(table_name: str, row_id: int):
    """Delete a row from any table by ID."""

    import re
    if not re.match(r'^[a-zA-Z0-9_]+$', table_name):
        raise HTTPException(status_code=400, detail="Invalid table name")

    try:
        with get_connection() as (_, cursor):
            cursor.execute(f"SELECT id FROM {table_name} WHERE id = %s", (row_id,))
            if not cursor.fetchone():
                raise HTTPException(status_code=404, detail="Row not found")
            
            cursor.execute(f"DELETE FROM {table_name} WHERE id = %s", (row_id,))
        
        return None
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete: {str(e)}")
