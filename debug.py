import os
from qdrant_client import QdrantClient

QDRANT_URL = os.getenv("QDRANT_URL")
QDRANT_API_KEY = os.getenv("QDRANT_API_KEY")

print("QDRANT_URL =", QDRANT_URL)
print("QDRANT_API_KEY set =", bool(QDRANT_API_KEY))

client = QdrantClient(
    url=QDRANT_URL,
    api_key=QDRANT_API_KEY,
    prefer_grpc=False,
    timeout=10.0,
)

print("Server info:")
print(client.get_collections())
