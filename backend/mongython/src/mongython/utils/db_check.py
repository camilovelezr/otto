"""MongoDB connection check utility.

This script can be used to diagnose MongoDB connection issues.
Run it directly to test your MongoDB connection.
"""

import os
import sys
import asyncio
import logging
import socket
from urllib.parse import urlparse

from motor.motor_asyncio import AsyncIOMotorClient
from pymongo.errors import ServerSelectionTimeoutError
from dotenv import load_dotenv, find_dotenv

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
)
logger = logging.getLogger(__name__)


async def check_mongodb_connection():
    """Test MongoDB connectivity and provide diagnostic information."""
    # Load environment variables
    load_dotenv(override=True, dotenv_path=find_dotenv())
    mongo_uri = os.getenv("MONGO_URI")

    if not mongo_uri:
        logger.error("MONGO_URI environment variable is not set!")
        return False

    # Parse MongoDB URI
    parsed_uri = urlparse(mongo_uri)
    host = parsed_uri.hostname or "localhost"
    port = parsed_uri.port or 27017
    db_name = parsed_uri.path.strip("/") or "otto"

    # Log sanitized connection info
    sanitized_uri = (
        f"{parsed_uri.scheme}://{parsed_uri.netloc.split('@')[-1]}{parsed_uri.path}"
    )
    logger.info(f"Testing connection to MongoDB at: {sanitized_uri}")

    # 1. Check if host is reachable at network level
    try:
        logger.info(f"Checking if host {host} is reachable...")
        socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)
        logger.info(f"Host {host} is reachable at network level")
    except socket.gaierror as e:
        logger.error(f"Host {host} is not reachable: {str(e)}")
        logger.error("Network connectivity issue detected")
        return False

    # 2. Try to connect to MongoDB
    try:
        logger.info("Attempting to connect to MongoDB...")
        client = AsyncIOMotorClient(mongo_uri, serverSelectionTimeoutMS=5000)

        # Check server info
        server_info = await client.admin.command("ismaster")
        logger.info(
            f"Successfully connected to MongoDB server version: {server_info.get('version', 'unknown')}"
        )

        # Check database existence
        db_list = await client.list_database_names()
        logger.info(f"Available databases: {', '.join(db_list)}")

        if db_name in db_list:
            logger.info(f"Database '{db_name}' exists")
        else:
            logger.warning(
                f"Database '{db_name}' does not exist yet, but will be created on first use"
            )

        # Check collections if database exists
        if db_name in db_list:
            collections = await client[db_name].list_collection_names()
            logger.info(
                f"Collections in {db_name}: {', '.join(collections) if collections else 'none'}"
            )

        logger.info("MongoDB connection check successful!")
        return True

    except ServerSelectionTimeoutError as e:
        logger.error(f"MongoDB server selection timeout: {str(e)}")
        logger.error(
            "MongoDB service may not be running or is not accessible with current credentials"
        )
        return False
    except Exception as e:
        logger.error(f"Error connecting to MongoDB: {str(e)}")
        return False


def main():
    """Run the MongoDB connection check."""
    logger.info("Starting MongoDB connection check utility")
    result = asyncio.run(check_mongodb_connection())

    if result:
        logger.info("MongoDB connection check PASSED")
        return 0
    else:
        logger.error("MongoDB connection check FAILED")
        return 1


if __name__ == "__main__":
    sys.exit(main())
