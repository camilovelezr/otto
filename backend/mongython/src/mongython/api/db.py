"""Database connection management for the API."""

import logging
import os
import socket
import time
from contextlib import asynccontextmanager
from urllib.parse import urlparse

from beanie import init_beanie
from fastapi import FastAPI
from motor.motor_asyncio import AsyncIOMotorClient
from pymongo.errors import ServerSelectionTimeoutError, ConnectionFailure
from dotenv import load_dotenv, find_dotenv
from bson.codec_options import CodecOptions
from bson.binary import UuidRepresentation

from mongython.models.user import User
from mongython.models.llm_model import LLMModel
from mongython.models.conversation import Conversation
from mongython.models.message import Message

logger = logging.getLogger(__name__)

# Maximum number of connection attempts
MAX_CONNECTION_ATTEMPTS = 3
# Seconds to wait between connection attempts
CONNECTION_RETRY_DELAY = 2

# Load environment variables
load_dotenv(override=True, dotenv_path=find_dotenv())
MONGO_URI = os.getenv("MONGO_URI")

if not MONGO_URI:
    logger.critical(
        "MONGO_URI environment variable is not set! Using default mongodb://localhost:27017/otto"
    )
    MONGO_URI = "mongodb://localhost:27017/otto"

# Log MongoDB connection info (without credentials)
parsed_uri = urlparse(MONGO_URI)
sanitized_uri = (
    f"{parsed_uri.scheme}://{parsed_uri.netloc.split('@')[-1]}{parsed_uri.path}"
)
logger.info(f"Connecting to MongoDB at: {sanitized_uri}")


# Function to create a MongoDB client with retry logic
def create_mongo_client(uri, attempts=MAX_CONNECTION_ATTEMPTS):
    for attempt in range(1, attempts + 1):
        try:
            logger.info(
                f"Attempting to create MongoDB client (attempt {attempt}/{attempts})"
            )
            client = AsyncIOMotorClient(
                uri, 
                serverSelectionTimeoutMS=5000,
                uuidRepresentation='standard'  # Use standard UUID representation
            )
            return client
        except Exception as e:
            if attempt == attempts:
                logger.critical(
                    f"Failed to create MongoDB client after {attempts} attempts: {str(e)}"
                )
                raise
            logger.warning(
                f"Failed to create MongoDB client (attempt {attempt}/{attempts}): {str(e)}"
            )
            logger.info(f"Retrying in {CONNECTION_RETRY_DELAY} seconds...")
            time.sleep(CONNECTION_RETRY_DELAY)


# Create database client with retry logic
client = create_mongo_client(MONGO_URI)


async def migrate_database(db):
    """Migrate database to latest schema."""
    logger.info("Starting database migration")
    try:
        # Drop the messages collection to force schema update
        await db.drop_collection("messages")
        logger.info("Dropped messages collection for schema update")
        
        # Reinitialize Beanie with new schema
        await init_beanie(
            database=db,
            document_models=[User, LLMModel, Conversation, Message],
        )
        logger.info("Successfully migrated database schema")
    except Exception as e:
        logger.error(f"Failed to migrate database: {e}")
        raise

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize database connection on startup and close on shutdown."""
    logger.info("Initializing database connection")
    for attempt in range(1, MAX_CONNECTION_ATTEMPTS + 1):
        try:
            # Verify database connectivity before initializing Beanie
            await client.admin.command("ping")
            logger.info("Successfully connected to MongoDB server")

            db_name = parsed_uri.path.strip("/") or "otto"
            logger.info(f"Using database: {db_name}")

            # Configure the database with proper UUID handling
            db = client[db_name]
            db = db.with_options(
                codec_options=CodecOptions(uuid_representation=UuidRepresentation.STANDARD)
            )

            # Migrate database if needed
            await migrate_database(db)
            logger.info("Database connection established")
            break
        except (ServerSelectionTimeoutError, ConnectionFailure) as e:
            if attempt == MAX_CONNECTION_ATTEMPTS:
                error_message = generate_db_error_message()
                logger.critical(f"{error_message}. Error: {str(e)}")
                raise

            logger.warning(
                f"Database connection failed (attempt {attempt}/{MAX_CONNECTION_ATTEMPTS}): {str(e)}"
            )
            logger.info(f"Retrying in {CONNECTION_RETRY_DELAY} seconds...")
            time.sleep(CONNECTION_RETRY_DELAY)
        except Exception as e:
            logger.critical(f"Failed to initialize database: {str(e)}")
            raise
    yield
    logger.info("Shutting down application")


def generate_db_error_message():
    """Generate a helpful error message for database connection issues."""
    host = parsed_uri.hostname or "localhost"
    port = parsed_uri.port or 27017

    # Check if host is reachable
    try:
        socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)
        is_reachable = True
    except socket.gaierror:
        is_reachable = False

    if not is_reachable:
        return f"Cannot reach MongoDB host {host}:{port} - Check network connectivity or MongoDB service"
    else:
        return f"MongoDB at {host}:{port} is reachable but connection failed - Check if MongoDB service is running"
