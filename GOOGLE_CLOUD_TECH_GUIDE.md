# Google Cloud Services — Practical Tech Guide

A concise, opinionated guide for building applications on Google Cloud infrastructure. Covers service selection, usage patterns, and pitfalls.

---

## Table of Contents

1. [Vertex AI / Gemini](#1-vertex-ai--gemini)
2. [Agent Development Kit (ADK)](#2-agent-development-kit-adk)
3. [Model Context Protocol (MCP)](#3-model-context-protocol-mcp)
4. [Cloud Spanner](#4-cloud-spanner)
5. [Firestore](#5-firestore)
6. [BigQuery](#6-bigquery)
7. [Cloud Storage (GCS)](#7-cloud-storage-gcs)
8. [Firebase Auth](#8-firebase-auth)
9. [Firebase Storage](#9-firebase-storage)
10. [Cloud Run](#10-cloud-run)
11. [Cloud Build & Artifact Registry](#11-cloud-build--artifact-registry)
12. [IAM & Service Accounts](#12-iam--service-accounts)
13. [A2A Protocol & Kafka](#13-a2a-protocol--kafka)
14. [Service Selection Matrix](#14-service-selection-matrix)
15. [Anti-Patterns](#15-anti-patterns)

---

## 1. Vertex AI / Gemini

Google's managed AI platform. Use Gemini models for text, vision, image generation, and real-time streaming.

### Setup

```bash
gcloud services enable aiplatform.googleapis.com
pip install google-genai
```

### Client Initialization

```python
from google import genai
from google.genai import types

# Always use Vertex AI backend (not AI Studio) for production
client = genai.Client(vertexai=True, project="my-project", location="us-central1")
```

### Text Generation

```python
response = client.models.generate_content(
    model="gemini-2.5-flash",
    contents="Summarize this document...",
)
print(response.text)
```

### Vision (Image/Video Analysis)

```python
response = client.models.generate_content(
    model="gemini-2.5-flash",
    contents=[
        types.Part.from_bytes(data=image_bytes, mime_type="image/png"),
        "Describe what you see in this image.",
    ],
)
```

For files already in GCS:

```python
types.Part.from_uri(file_uri="gs://my-bucket/image.png", mime_type="image/png")
```

### Image Generation (Multi-turn for Consistency)

```python
# Use a chat session to maintain visual consistency across multiple images
chat = client.chats.create(
    model="gemini-2.0-flash-preview-image-generation",
    config=types.GenerateContentConfig(
        response_modalities=["IMAGE", "TEXT"],
    ),
)

# Turn 1: Generate base image
response = chat.send_message("Create a product logo with blue gradients")
# Turn 2: Generate variant — same session keeps style consistent
response = chat.send_message("Now create a favicon version of the same logo")

# Extract generated image
for part in response.candidates[0].content.parts:
    if part.inline_data:
        image_bytes = part.inline_data.data
```

### Real-time Streaming (Gemini Live API)

For bidirectional audio/video streaming (voice assistants, real-time analysis):

```python
async with client.aio.live.connect(
    model="gemini-live-2.5-flash-preview-native-audio",
    config=types.LiveConnectConfig(
        response_modalities=["AUDIO"],
        system_instruction="You are a helpful assistant...",
        tools=[{"function_declarations": [...]}],
    ),
) as session:
    # Send audio/video frames
    await session.send(input=types.LiveClientContent(
        turns=[types.Content(parts=[
            types.Part(inline_data=types.Blob(data=audio_chunk, mime_type="audio/pcm")),
        ])]
    ))

    # Receive streaming responses
    async for msg in session.receive():
        if msg.server_content and msg.server_content.model_turn:
            for part in msg.server_content.model_turn.parts:
                if part.inline_data:
                    # audio response bytes
                    pass
        if msg.tool_call:
            # handle tool calls inline
            pass

    await session.send(input=types.LiveClientContent(turn_complete=True))
```

### When to Use Which Model

| Model | Use Case |
|-------|----------|
| `gemini-2.5-flash` | General text, vision, code — fast and cheap |
| `gemini-2.5-pro` | Complex reasoning, long documents |
| `gemini-2.0-flash-preview-image-generation` | Image generation + text |
| `gemini-live-2.5-flash-preview-native-audio` | Real-time audio/video streaming |
| `text-embedding-005` | Vector embeddings for search |

### Best Practices

- **Use `vertexai=True`** for production. AI Studio keys are for prototyping only.
- **Single chat session** for related image generations — maintains character/style consistency.
- **`gs://` URIs** work directly in Gemini — no need to download files first.
- **Always set `safety_settings`** in production to control content filtering.
- **Stream responses** for user-facing applications to reduce perceived latency.

### Avoid

- Sending raw base64 when a GCS URI exists — wastes bandwidth and tokens.
- Using `gemini-2.5-pro` for simple tasks — Flash is 10x cheaper and fast enough.
- Blocking on Live API without `turn_complete` — the model waits indefinitely.

---

## 2. Agent Development Kit (ADK)

Google's framework for building AI agents with tool use, multi-agent orchestration, and state management.

### Setup

```bash
pip install google-adk
```

### Basic Agent

```python
from google.adk.agents import Agent

agent = Agent(
    model="gemini-2.5-flash",
    name="my_agent",
    instruction="You are a helpful assistant that answers questions about products.",
    tools=[search_products, get_product_details],
)
```

### Tool Functions

```python
from google.adk.tools import FunctionTool, ToolContext

def search_products(query: str, tool_context: ToolContext) -> str:
    """Search the product catalog by keyword."""
    # Access shared state
    user_id = tool_context.state["user_id"]
    results = db.search(query, user_id=user_id)
    # Update state for downstream tools
    tool_context.state["last_search_results"] = results
    return json.dumps(results)
```

- **`ToolContext`** gives tools access to the shared agent state.
- Docstrings become the tool description the model sees — make them clear.
- Return strings (or JSON strings). The framework serializes for you.

### State Templating

Agent instructions auto-interpolate from state using `{key}` syntax:

```python
agent = Agent(
    model="gemini-2.5-flash",
    name="support_agent",
    instruction="""You are helping user {user_name} (ID: {user_id}).
    Their subscription tier is {tier}. Answer accordingly.""",
)
```

State is populated via `before_agent_callback` or by parent agents.

### Lifecycle Callbacks

```python
def before_agent(callback_context):
    """Runs before each agent turn. Use for dynamic context loading."""
    state = callback_context.state
    user = fetch_user(state["user_id"])
    state["user_name"] = user.name
    state["tier"] = user.subscription_tier

agent = Agent(
    model="gemini-2.5-flash",
    name="support_agent",
    instruction="Help {user_name} with their {tier} account.",
    before_agent_callback=before_agent,
    tools=[...],
)
```

Use `before_agent_callback` for API calls, DB lookups, or any setup that depends on runtime state.

### Multi-Agent Patterns

#### Parallel Execution (Independent Tasks)

```python
from google.adk.agents import ParallelAgent

# All sub-agents run concurrently — results merge when all complete
analysis_crew = ParallelAgent(
    name="analysis_crew",
    sub_agents=[sentiment_agent, entity_agent, summary_agent],
)
```

Use when sub-tasks don't depend on each other. N agents run in ~1x time instead of Nx.

#### Sequential Pipeline (Ordered Steps)

```python
from google.adk.agents import SequentialAgent

pipeline = SequentialAgent(
    name="etl_pipeline",
    sub_agents=[validate_agent, transform_agent, load_agent, notify_agent],
)
```

Each step's output feeds the next. Use for workflows with strict ordering.

#### Delegating to Sub-Agents

```python
root = Agent(
    model="gemini-2.5-flash",
    name="router",
    instruction="Route to the appropriate specialist based on the user's question.",
    sub_agents=[billing_agent, technical_agent, sales_agent],
)
```

The root agent decides which sub-agent handles each request.

### Best Practices

- **Compose, don't monolith.** Break complex workflows into focused agents.
- **`ParallelAgent`** for independent tasks; **`SequentialAgent`** for pipelines.
- **State is the shared bus.** Use `tool_context.state` for inter-tool communication.
- **Name agents descriptively** — the model uses the name to decide delegation.

### Avoid

- Putting too many tools on a single agent — split into specialists.
- Using `before_agent_callback` for heavy computation — it runs on every turn.
- Circular sub-agent references — agents should form a DAG.

---

## 3. Model Context Protocol (MCP)

Standard protocol for exposing tools to AI agents. Deploy tool servers that any MCP-compatible agent can call.

### Building a Custom MCP Server

```python
from fastmcp import FastMCP

mcp = FastMCP("my-tool-server")

@mcp.tool()
async def analyze_document(document_url: str) -> str:
    """Analyze a document and return key findings."""
    content = fetch_document(document_url)
    analysis = run_analysis(content)
    return json.dumps(analysis)

@mcp.tool()
async def search_database(query: str, limit: int = 10) -> str:
    """Search the internal database for matching records."""
    results = db.search(query, limit=limit)
    return json.dumps(results)

if __name__ == "__main__":
    mcp.run(transport="streamable-http", host="0.0.0.0", port=8080)
```

Deploy to Cloud Run and any agent can connect via HTTP.

### Connecting Agents to Custom MCP Servers

```python
from google.adk.tools.mcp_tool import MCPToolset, StreamableHTTPConnectionParams

tools, exit_stack = await MCPToolset.from_server(
    connection_params=StreamableHTTPConnectionParams(
        url="https://my-mcp-server-abc123.run.app/mcp",
    ),
)

agent = Agent(
    model="gemini-2.5-flash",
    name="analyst",
    tools=tools,
)
```

### Google Cloud Managed MCP Servers

Google provides pre-built MCP servers for BigQuery, Spanner, and other services:

```python
bigquery_tools, _ = await MCPToolset.from_server(
    connection_params=StreamableHTTPConnectionParams(
        url=f"https://mcp.googleapis.com/v1alpha/projects/{PROJECT}/locations/us-central1/mcpServers/bigquery",
        headers={"Content-Type": "application/json"},
    ),
    # Only expose the tools this agent needs
    tool_filter=["execute_sql", "list_table_ids", "get_table_information"],
)
```

### Best Practices

- **`streamable-http` transport** for Cloud Run deployments (not stdio).
- **`tool_filter`** to restrict which tools an agent can access — limits blast radius.
- **Combine local + remote tools** in a single agent for hybrid approaches.
- **One MCP server per domain** — don't put unrelated tools together.

### Avoid

- Exposing write/delete operations without authentication on the MCP server.
- Letting agents access every tool on a large MCP server — use `tool_filter`.
- Using stdio transport for production deployments — it's for local development only.

---

## 4. Cloud Spanner

Globally distributed, strongly consistent relational database. Supports SQL, graph queries (GQL), and vector search.

### When to Use Spanner

- You need **global distribution** with strong consistency.
- Your data has **complex relationships** (graph queries with GQL).
- You need **SQL + vector search** in the same database.
- You need **horizontal scaling** beyond what Cloud SQL offers.

**Don't use Spanner** for simple key-value lookups (use Firestore) or analytics-heavy workloads (use BigQuery).

### Setup

```bash
gcloud services enable spanner.googleapis.com
pip install google-cloud-spanner
```

### Basic Operations

```python
from google.cloud import spanner

client = spanner.Client(project="my-project")
instance = client.instance("my-instance")
database = instance.database("my-database")

# Read with snapshot (consistent reads)
with database.snapshot() as snapshot:
    results = snapshot.execute_sql(
        "SELECT name, email FROM Users WHERE id = @user_id",
        params={"user_id": "abc123"},
        param_types={"user_id": spanner.param_types.STRING},
    )
    for row in results:
        print(row)

# Write with batch (atomic multi-row inserts)
with database.batch() as batch:
    batch.insert(
        table="Users",
        columns=["id", "name", "email"],
        values=[["abc123", "Alice", "alice@example.com"]],
    )

# Write with transaction (read-then-write)
def update_balance(transaction):
    row = transaction.read("Accounts", columns=["balance"], keyset=KeySet(keys=[["abc"]]))
    current = list(row)[0][0]
    transaction.update("Accounts", columns=["id", "balance"], values=[["abc", current + 100]])

database.run_in_transaction(update_balance)
```

### Graph Queries (GQL)

Spanner supports property graph queries for relationship traversal:

```python
gql_query = """
GRAPH MyGraph
MATCH (u:User)-[r:FOLLOWS]->(f:User)
WHERE u.name = 'Alice'
RETURN f.name, r.since
"""

with database.snapshot() as snapshot:
    results = snapshot.execute_sql(gql_query)
    for row in results:
        print(row)
```

```python
# Path finding
gql_query = """
GRAPH MyGraph
MATCH path = (a:User)-[:KNOWS*1..3]->(b:User)
WHERE a.name = 'Alice' AND b.name = 'Charlie'
RETURN path
"""
```

### Vector Search (Embeddings)

```python
# Store embeddings alongside data
batch.insert(
    table="Documents",
    columns=["id", "content", "embedding"],
    values=[["doc1", "Some text", embedding_vector]],
)

# Nearest neighbor search
query = """
SELECT id, content, COSINE_DISTANCE(embedding, @query_embedding) as distance
FROM Documents
ORDER BY distance
LIMIT 10
"""
```

### Best Practices

- Use **`snapshot()`** for read-only queries — avoids transaction overhead.
- Use **`batch()`** for bulk inserts — atomic and faster than individual writes.
- Use **`run_in_transaction()`** for read-modify-write patterns.
- **GQL** for relationship traversal; **SQL** for simple lookups and aggregations.
- Store **vector embeddings** in Spanner for hybrid search (semantic + keyword + graph).

### Avoid

- Using Spanner for tiny datasets — it's expensive at small scale. Use Firestore.
- Read-modify-write outside transactions — leads to stale data.
- Hotspot keys (e.g., auto-incrementing integers) — use UUIDs or hashed prefixes.
- Running full table scans on large tables — always have appropriate indexes.

---

## 5. Firestore

Serverless NoSQL document database. Best for real-time apps, user profiles, and event-driven architectures.

### When to Use Firestore

- **Key-value or document lookups** (user profiles, settings, sessions).
- **Real-time listeners** (live dashboards, collaborative apps).
- **Rapid prototyping** — zero schema, auto-scaling, generous free tier.

**Don't use Firestore** for complex joins, analytics, or full-text search.

### Setup

```bash
gcloud services enable firestore.googleapis.com
pip install google-cloud-firestore
```

### Async Operations (for FastAPI / async frameworks)

```python
from google.cloud.firestore import AsyncClient, FieldFilter
from google.cloud import firestore

db = AsyncClient(project="my-project")

# Create document
doc_ref = db.collection("users").document("user123")
await doc_ref.set({
    "name": "Alice",
    "email": "alice@example.com",
    "created_at": firestore.SERVER_TIMESTAMP,
})

# Read document
doc = await doc_ref.get()
if doc.exists:
    data = doc.to_dict()

# Query with filters
query = db.collection("users").where(
    filter=FieldFilter("role", "==", "admin")
).order_by("created_at").limit(10)

results = [doc async for doc in query.stream()]

# Atomic increment (no read-modify-write needed)
await doc_ref.update({
    "login_count": firestore.Increment(1),
    "last_login": firestore.SERVER_TIMESTAMP,
})

# Batch writes (atomic across documents)
batch = db.batch()
batch.set(db.collection("users").document("a"), {"name": "A"})
batch.set(db.collection("users").document("b"), {"name": "B"})
await batch.commit()
```

### Case-Insensitive Queries

Firestore has no `ILIKE`. Store a lowercase copy:

```python
await doc_ref.set({
    "username": "AliceSmith",
    "username_lower": "alicesmith",  # for case-insensitive lookups
})

# Query the lowercase field
query = db.collection("users").where(
    filter=FieldFilter("username_lower", "==", search_term.lower())
)
```

### Best Practices

- Use **`AsyncClient`** in async frameworks (FastAPI, aiohttp) — sync client blocks the event loop.
- Use **`firestore.Increment()`** for counters — atomic, no race conditions.
- Use **`SERVER_TIMESTAMP`** for created/updated fields — consistent across clients.
- **Flatten documents** where possible — deeply nested data is hard to query.
- Use **batch writes** for multi-document atomicity (max 500 operations).

### Avoid

- Complex queries with multiple inequality filters on different fields — Firestore doesn't support this well.
- Storing large blobs (>1MB) in documents — use Cloud Storage and store the URL.
- Using sync client in async code — causes thread blocking and poor performance.
- Over-nesting subcollections — hard to query across; prefer root collections with reference fields.

---

## 6. BigQuery

Serverless data warehouse for analytics. Best for large-scale queries, data exploration, and ML pipelines.

### When to Use BigQuery

- **Analytical queries** over large datasets (TBs+).
- **Ad-hoc exploration** of structured/semi-structured data.
- **ML pipelines** — BigQuery ML for in-database model training.
- **Data sharing** — public datasets, cross-project queries.

**Don't use BigQuery** for transactional workloads or low-latency lookups.

### Setup

```bash
gcloud services enable bigquery.googleapis.com
pip install google-cloud-bigquery
```

### Basic Operations

```python
from google.cloud import bigquery

client = bigquery.Client(project="my-project")

# Create dataset and table
dataset = bigquery.Dataset("my-project.my_dataset")
client.create_dataset(dataset, exists_ok=True)

schema = [
    bigquery.SchemaField("id", "STRING", mode="REQUIRED"),
    bigquery.SchemaField("name", "STRING"),
    bigquery.SchemaField("score", "FLOAT64"),
    bigquery.SchemaField("created_at", "TIMESTAMP"),
]
table = bigquery.Table("my-project.my_dataset.my_table", schema=schema)
client.create_table(table, exists_ok=True)

# Query
query = """
SELECT name, AVG(score) as avg_score
FROM `my-project.my_dataset.my_table`
GROUP BY name
ORDER BY avg_score DESC
LIMIT 10
"""
results = client.query(query)
for row in results:
    print(f"{row.name}: {row.avg_score}")

# Insert rows
rows = [
    {"id": "1", "name": "Alice", "score": 95.0},
    {"id": "2", "name": "Bob", "score": 87.5},
]
errors = client.insert_rows_json("my-project.my_dataset.my_table", rows)
if errors:
    print(f"Insert errors: {errors}")
```

### Accessing BigQuery from Agents via MCP

Rather than writing custom SQL tools, use Google Cloud's managed BigQuery MCP server:

```python
from google.adk.tools.mcp_tool import MCPToolset, StreamableHTTPConnectionParams

bq_tools, _ = await MCPToolset.from_server(
    connection_params=StreamableHTTPConnectionParams(
        url=f"https://mcp.googleapis.com/v1alpha/projects/{PROJECT}/locations/us-central1/mcpServers/bigquery",
        headers={"Content-Type": "application/json"},
    ),
    tool_filter=["execute_sql", "list_dataset_ids", "list_table_ids", "get_table_information"],
)
```

The agent can then explore schemas and run queries autonomously.

### Best Practices

- Use **`exists_ok=True`** for idempotent setup scripts.
- **Parameterize queries** to prevent SQL injection when accepting user input.
- Use **Google Cloud MCP** for agent access — no need for custom SQL tool wrappers.
- **Partition tables** by date for cost and performance optimization.
- Use **`tool_filter`** to limit agent access to read-only operations.

### Avoid

- Using BigQuery for OLTP (transactional) workloads — it's designed for analytics.
- Full table scans on huge tables without filters — costs add up fast.
- Streaming inserts for batch data — use load jobs instead (cheaper, faster for bulk).

---

## 7. Cloud Storage (GCS)

Object storage for files of any size. The backbone for media, backups, and data pipelines.

### Setup

```bash
gcloud services enable storage.googleapis.com
pip install google-cloud-storage
```

### Basic Operations

```python
from google.cloud import storage
from datetime import timedelta

client = storage.Client(project="my-project")
bucket = client.bucket("my-bucket")

# Upload
blob = bucket.blob("uploads/report.pdf")
blob.upload_from_filename("/tmp/report.pdf")
# Or from bytes
blob.upload_from_string(file_bytes, content_type="application/pdf")

# Download
blob.download_to_filename("/tmp/downloaded.pdf")
# Or to bytes
content = blob.download_as_bytes()

# Generate signed URL (time-limited access without authentication)
signed_url = blob.generate_signed_url(
    version="v4",
    expiration=timedelta(hours=1),
    method="GET",
)

# Make permanently public (use sparingly)
blob.make_public()
public_url = blob.public_url

# Delete
blob.delete()

# List objects
for blob in bucket.list_blobs(prefix="uploads/"):
    print(blob.name)
```

### GCS URIs with Gemini

Gemini models can read GCS files directly — no download needed:

```python
# Instead of downloading and re-uploading:
response = client.models.generate_content(
    model="gemini-2.5-flash",
    contents=[
        types.Part.from_uri(file_uri="gs://my-bucket/image.png", mime_type="image/png"),
        "Describe this image.",
    ],
)
```

### Best Practices

- **Organize with path prefixes:** `avatars/`, `uploads/`, `exports/`, `backups/`.
- **Use `gs://` URIs** for service-to-service references (Gemini, BigQuery, Dataflow all support them).
- **Signed URLs** for temporary external access — don't make buckets public.
- **Set lifecycle rules** to auto-delete temporary files after N days.
- **Use `content_type`** when uploading — prevents browser download instead of display.

### Avoid

- Making entire buckets public — use signed URLs or IAM per-object.
- Storing sensitive data without encryption configuration — enable CMEK for regulated data.
- Downloading files just to pass them to another GCP service — use `gs://` URIs.
- Flat object naming without prefixes — makes listing and management painful.

---

## 8. Firebase Auth

Managed authentication service. Handles sign-up, sign-in, token verification, and identity providers.

### Setup

```bash
pip install firebase-admin
```

### Server-Side Token Verification

```python
import firebase_admin
from firebase_admin import auth

# Initialize once at app startup
firebase_admin.initialize_app()

# Verify ID token from client
def verify_token(authorization_header: str) -> dict:
    token = authorization_header.replace("Bearer ", "")
    try:
        decoded = auth.verify_id_token(token)
        return decoded  # Contains uid, email, name, etc.
    except auth.InvalidIdTokenError:
        raise HTTPException(401, "Invalid token")
    except auth.ExpiredIdTokenError:
        raise HTTPException(401, "Token expired")
```

### FastAPI Dependency Pattern

```python
from fastapi import Depends, Header, HTTPException

async def get_current_user(authorization: str = Header(...)) -> dict:
    return verify_token(authorization)

async def require_admin(user: dict = Depends(get_current_user)) -> dict:
    # Check admin status against a config store (Firestore, env var, etc.)
    admins = await get_admin_emails()
    if user.get("email") not in admins:
        raise HTTPException(403, "Admin access required")
    return user

@app.get("/admin/dashboard")
async def admin_dashboard(user: dict = Depends(require_admin)):
    return {"message": f"Welcome admin {user['email']}"}
```

### Best Practices

- **Verify tokens server-side** — never trust client-side claims alone.
- Store **admin lists in Firestore/config** — not hardcoded in source.
- Use **Firebase ID tokens** (not custom tokens) for standard web auth.
- Handle **`ExpiredIdTokenError`** separately — clients should refresh, not re-login.

### Avoid

- Storing passwords yourself — let Firebase handle credential management.
- Trusting client-provided user info without token verification.
- Putting admin checks in frontend code only — always enforce server-side.

---

## 9. Firebase Storage

Wrapper around GCS with Firebase Auth integration and client SDK support. Best for user-uploaded content in Firebase apps.

### Setup

```python
import firebase_admin
from firebase_admin import storage

firebase_admin.initialize_app(options={
    "storageBucket": "my-project.firebasestorage.app"
})

bucket = storage.bucket()
```

### Upload and Serve

```python
def upload_user_avatar(user_id: str, image_bytes: bytes) -> str:
    blob = bucket.blob(f"avatars/{user_id}.png")
    blob.upload_from_string(image_bytes, content_type="image/png")
    blob.make_public()
    return blob.public_url

def delete_user_avatar(user_id: str):
    blob = bucket.blob(f"avatars/{user_id}.png")
    if blob.exists():
        blob.delete()
```

### When to Use Firebase Storage vs. GCS Directly

| Use Firebase Storage | Use GCS Directly |
|---------------------|------------------|
| User-facing uploads with Firebase Auth | Server-to-server file processing |
| Client SDK (web/mobile) uploads | Data pipelines and ETL |
| Firebase Security Rules for access control | Fine-grained IAM policies |

### Best Practices

- **`make_public()`** only for intentionally public assets (avatars, icons).
- **Check `exists()`** before delete to avoid errors.
- **Namespace by user ID** in paths: `avatars/{uid}.png`, `uploads/{uid}/`.

---

## 10. Cloud Run

Fully managed container platform. Deploy any Docker container and get auto-scaling, HTTPS, and custom domains.

### Dockerfile Patterns

#### Python (FastAPI)

```dockerfile
FROM python:3.11-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --target=/app/deps -r requirements.txt

FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /app/deps /usr/local/lib/python3.11/site-packages/
COPY . .

RUN adduser --disabled-password --gecos '' appuser
USER appuser

EXPOSE 8080
HEALTHCHECK CMD curl -f http://localhost:8080/health || exit 1
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

#### Node.js (Next.js)

```dockerfile
FROM node:20-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

USER node
EXPOSE 3000
CMD ["node", "server.js"]
```

### Deploy

```bash
# Build and deploy in one command
gcloud run deploy my-service \
    --source . \
    --region us-central1 \
    --allow-unauthenticated \
    --memory 512Mi \
    --set-env-vars="PROJECT_ID=$PROJECT_ID,ENV=production"

# Or build separately via Cloud Build
gcloud builds submit --tag us-central1-docker.pkg.dev/$PROJECT_ID/my-repo/my-image
gcloud run deploy my-service \
    --image us-central1-docker.pkg.dev/$PROJECT_ID/my-repo/my-image \
    --region us-central1
```

### WebSocket Support

Cloud Run supports WebSockets — use for real-time features:

```python
from fastapi import WebSocket

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    while True:
        data = await websocket.receive_text()
        await websocket.send_text(f"Echo: {data}")
```

### Best Practices

- **Multi-stage Docker builds** — dramatically reduces image size.
- **Non-root user** — always add `USER appuser` or `USER node`.
- **Port 8080** — Cloud Run default. Set via `PORT` env var or `EXPOSE`.
- **Health checks** — add `GET /health` endpoint for uptime monitoring.
- **`--no-cache-dir`** with pip — reduces Docker layer size.
- **`--allow-unauthenticated`** only for public APIs — use IAM for internal services.
- **Min instances = 1** for latency-sensitive services (avoids cold starts).

### Avoid

- Running as root in production containers.
- Large base images (`python:3.11` vs `python:3.11-slim`) — wastes build/pull time.
- Storing state in-memory (Cloud Run instances are ephemeral) — use Firestore/Redis/Spanner.
- Setting excessive memory/CPU — start small (256Mi/1 CPU), scale up based on metrics.

---

## 11. Cloud Build & Artifact Registry

### Cloud Build — CI/CD Pipelines

```yaml
steps:
  # Build Docker image
  - name: 'gcr.io/cloud-builders/docker'
    args: ['build', '-t', '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO}/${_IMAGE}', '.']

  # Push to Artifact Registry
  - name: 'gcr.io/cloud-builders/docker'
    args: ['push', '${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO}/${_IMAGE}']

  # Deploy to Cloud Run
  - name: 'gcr.io/google.com/cloudsdktool/cloud-sdk'
    args:
      - gcloud
      - run
      - deploy
      - ${_SERVICE_NAME}
      - --image=${_REGION}-docker.pkg.dev/${PROJECT_ID}/${_REPO}/${_IMAGE}
      - --region=${_REGION}
      - --platform=managed
      - --allow-unauthenticated
      - --memory=${_MEMORY}
      - --set-env-vars=PROJECT_ID=${PROJECT_ID}

substitutions:
  _REGION: us-central1
  _REPO: my-repo
  _SERVICE_NAME: my-api
  _IMAGE: my-backend
  _MEMORY: 512Mi
  _SKIP_FRONTEND: 'false'  # Conditional builds

options:
  logging: CLOUD_LOGGING_ONLY
```

### Trigger Build

```bash
gcloud builds submit \
    --config=cloudbuild.yaml \
    --substitutions=_REGION=us-central1,_SERVICE_NAME=my-api
```

### Artifact Registry Setup

```bash
# Create Docker repository
gcloud artifacts repositories create my-repo \
    --repository-format=docker \
    --location=us-central1

# Authenticate Docker
gcloud auth configure-docker us-central1-docker.pkg.dev
```

### Best Practices

- **Use `substitutions`** for environment-specific values — never hardcode project IDs.
- **Artifact Registry** over Container Registry — GCR is deprecated.
- **Build → Push → Deploy** as the standard 3-step pipeline.
- **`_SKIP_*` substitutions** for conditional step execution (skip frontend-only changes).
- **Tag images** with commit SHA for traceability: `${_IMAGE}:${SHORT_SHA}`.

### Avoid

- Using `gcr.io` for new projects — it's deprecated. Use `*-docker.pkg.dev`.
- Storing secrets in `cloudbuild.yaml` — use Secret Manager references.
- Building without cache — use `--cache-from` for faster builds.

---

## 12. IAM & Service Accounts

### Standard Setup Script

```bash
#!/bin/bash
PROJECT_ID=$(gcloud config get-value project)
REGION="us-central1"

# 1. Enable required APIs
gcloud services enable \
    aiplatform.googleapis.com \
    run.googleapis.com \
    bigquery.googleapis.com \
    spanner.googleapis.com \
    firestore.googleapis.com \
    storage.googleapis.com \
    cloudbuild.googleapis.com \
    artifactregistry.googleapis.com

# 2. Create dedicated service account
SA_NAME="my-app-runner"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts create $SA_NAME \
    --display-name="My App Runner" \
    --quiet

# 3. Grant least-privilege roles
ROLES=(
    "roles/aiplatform.user"        # Vertex AI access
    "roles/bigquery.dataViewer"    # BigQuery read
    "roles/spanner.databaseReader" # Spanner read
    "roles/storage.objectViewer"   # GCS read
    "roles/run.invoker"            # Call other Cloud Run services
)

for ROLE in "${ROLES[@]}"; do
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="$ROLE" \
        --quiet
done

# 4. Deploy with specific service account
gcloud run deploy my-service \
    --service-account=$SA_EMAIL \
    --image=...
```

### Best Practices

- **One service account per workload** — not the default compute SA.
- **Least privilege** — `roles/aiplatform.user` not `roles/aiplatform.admin`.
- **Enable APIs first** — resource creation fails if the API isn't enabled.
- **`--quiet` flag** in scripts for non-interactive CI/CD execution.
- **Audit regularly** — `gcloud projects get-iam-policy $PROJECT_ID`.

### Avoid

- Using the default compute service account — it has overly broad permissions.
- Granting `roles/owner` or `roles/editor` to service accounts.
- Creating service account keys — use workload identity or attached SAs instead.
- Granting project-level roles when resource-level is sufficient.

---

## 13. A2A Protocol & Kafka

For distributed agent communication across services.

### Agent-to-Agent (A2A) Server

```python
from a2a.server.apps.starlette import A2AStarletteApplication
from a2a.server.request_handlers import DefaultRequestHandler
from a2a.server.tasks import InMemoryTaskStore
from a2a.types import AgentCard, AgentCapabilities

def create_a2a_server(agent_executor, host="0.0.0.0", port=8080):
    agent_card = AgentCard(
        name="my-agent",
        description="Handles specific domain tasks",
        url=f"http://{host}:{port}",
        capabilities=AgentCapabilities(streaming=True),
    )

    handler = DefaultRequestHandler(
        agent_executor=agent_executor,
        task_store=InMemoryTaskStore(),
    )

    return A2AStarletteApplication(
        agent_card=agent_card,
        http_handler=handler,
    )
```

### A2A Client (Calling Remote Agents)

```python
from a2a.client import A2AClient
from a2a.types import MessageSendParams, Message, Part

client = await A2AClient.get_client_from_agent_card_url(
    "http://remote-agent:8080/.well-known/agent.json"
)

response = await client.send_message(
    MessageSendParams(message=Message(
        role="user",
        parts=[Part(text="Process this request...")],
    ))
)
```

### Wrapping Remote Agents as ADK Tools

```python
from google.adk.agents import Agent
from google.adk.tools.agent_tool import AgentTool

remote_agent = RemoteA2aAgent(
    name="specialist",
    description="Handles specialized domain queries",
    agent_card_url="http://specialist-service:8081/.well-known/agent.json",
)

orchestrator = Agent(
    model="gemini-2.5-flash",
    name="orchestrator",
    tools=[AgentTool(agent=remote_agent), local_tool],
)
```

### Kafka for Event-Driven Agents

Use Kafka when agents need asynchronous, event-driven communication:

```python
# Server-Sent Events for real-time UI updates from Kafka consumers
from fastapi.responses import StreamingResponse

@app.get("/stream")
async def event_stream():
    async def generate():
        async for message in kafka_consumer:
            yield f"data: {json.dumps(message.value)}\n\n"
    return StreamingResponse(generate(), media_type="text/event-stream")
```

### Best Practices

- **A2A for synchronous** agent-to-agent calls; **Kafka for async** event streams.
- **`AgentCard`** enables service discovery — agents find each other by card URL.
- **`InMemoryTaskStore`** for stateless agents; use persistent stores for long-running tasks.
- **SSE** for browser real-time updates from backend event streams.

---

## 14. Service Selection Matrix

### Database Selection

| Need | Service | Why |
|------|---------|-----|
| Document/key-value storage | **Firestore** | Serverless, real-time listeners, flexible schema |
| Relational + graph + vector | **Cloud Spanner** | Global consistency, GQL, horizontal scale |
| Analytics on large datasets | **BigQuery** | Serverless warehouse, SQL, ML integration |
| Cache / ephemeral state | **Memorystore (Redis)** | Sub-ms latency, TTL, pub/sub |

### Compute Selection

| Need | Service | Why |
|------|---------|-----|
| HTTP APIs, microservices | **Cloud Run** | Auto-scaling containers, pay-per-request |
| Background jobs | **Cloud Run Jobs** | One-off or scheduled container execution |
| Event-driven functions | **Cloud Functions** | Single-purpose, triggered by events |
| Long-running VMs | **Compute Engine** | Full VM control, GPUs |

### AI/ML Selection

| Need | Service | Why |
|------|---------|-----|
| Text/vision/code generation | **Gemini via Vertex AI** | Managed, multi-modal, streaming |
| Agent orchestration | **ADK** | Multi-agent, tool use, state management |
| Tool interoperability | **MCP** | Standard protocol, Google Cloud managed servers |
| Embeddings/search | **Vertex AI Embeddings** | `text-embedding-005`, integrates with Spanner/BQ |
| Cross-service agents | **A2A Protocol** | Agent discovery, task delegation |

### Storage Selection

| Need | Service | Why |
|------|---------|-----|
| User uploads, media | **Cloud Storage** | Scalable, cheap, `gs://` URI ecosystem |
| Firebase app assets | **Firebase Storage** | Auth-integrated, client SDKs |
| Container images | **Artifact Registry** | Managed Docker registry |

---

## 15. Anti-Patterns

| Don't | Do Instead |
|-------|------------|
| Use default compute service account | Create dedicated SAs with minimal roles |
| Hardcode project IDs | Use env vars or `gcloud config get-value project` |
| Run containers as root | `USER appuser` in every Dockerfile |
| Use `gcr.io` for new projects | Use Artifact Registry (`*-docker.pkg.dev`) |
| Store secrets in code or YAML | Use Secret Manager or `--set-env-vars` at deploy |
| Use sync DB clients in async frameworks | Use `AsyncClient` for Firestore in FastAPI |
| Poll for real-time data | Use WebSockets, SSE, or Firestore listeners |
| Build monolithic agents | Compose with Parallel/Sequential/Remote agents |
| Download GCS files to pass to Gemini | Use `gs://` URIs directly — Gemini reads them |
| Grant `roles/owner` to service accounts | Use specific roles: `aiplatform.user`, `storage.objectViewer` |
| Use BigQuery for transactional workloads | Use Firestore or Spanner for OLTP |
| Make GCS buckets public | Use signed URLs for temporary access |
| Put all tools on one agent | Split into domain-specific specialist agents |
| Use stdio MCP transport in production | Use `streamable-http` for Cloud Run deployments |
