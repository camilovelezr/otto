"""Main API application."""

import logging
import os
import httpx
from pymongo.errors import ServerSelectionTimeoutError
import sys

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from fastapi.exceptions import RequestValidationError

from mongython.api.db import lifespan, client as mongo_client
from mongython.api.errors import (
    http_exception_handler,
    validation_exception_handler,
    handle_db_exception,
)
from mongython.api.users import router as users_router
from mongython.api.conversations import router as conversations_router
from mongython.api.models import router as models_router
from mongython.api.chat import router as chat_router
from dotenv import load_dotenv, find_dotenv
from mongython.models.user import User

# Load environment variables
load_dotenv(override=True, dotenv_path=find_dotenv())

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.StreamHandler(stream=sys.stdout),
        logging.FileHandler(filename="mongython_api.log", mode="a"),
    ],
)

# Configure specific loggers
logging.getLogger("mongython").setLevel(logging.DEBUG)
logging.getLogger("beanie").setLevel(logging.INFO)
logging.getLogger("motor").setLevel(logging.INFO)
logging.getLogger("uvicorn").setLevel(logging.INFO)

logger = logging.getLogger(__name__)

# Get environment variables at module level
LITELLM_URL = os.getenv("LITELLM_URL", "http://localhost:4000")
logger.info(f"LITELLM_URL: {LITELLM_URL}")


def create_application() -> FastAPI:
    """Create and configure the FastAPI application."""
    # Create FastAPI app
    app = FastAPI(
        lifespan=lifespan,
        title="User Management API",
        description="RESTful API for user management",
        version="1.0.0",
    )

    # Add CORS middleware
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],  # In production, replace with specific origins
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Add exception handlers
    app.add_exception_handler(HTTPException, http_exception_handler)
    app.add_exception_handler(RequestValidationError, validation_exception_handler)
    app.add_exception_handler(ServerSelectionTimeoutError, handle_db_exception)

    # Include routers
    app.include_router(users_router)
    app.include_router(conversations_router)
    app.include_router(models_router)
    app.include_router(chat_router)

    # Add health check endpoint
    @app.get("/", tags=["health"])
    async def health_check():
        """API health check endpoint."""
        return {"status": "ok", "message": "API is running"}

    @app.get("/health", tags=["health"])
    async def detailed_health_check():
        """Detailed health check endpoint that verifies MongoDB connectivity."""
        health_info = {"status": "ok", "api": "running", "mongodb": "unknown"}

        try:
            # Test MongoDB connection
            await mongo_client.admin.command("ping")
            health_info["mongodb"] = "connected"
        except Exception as e:
            health_info["status"] = "degraded"
            health_info["mongodb"] = "disconnected"
            health_info["mongodb_error"] = str(e)
            logger.warning(f"Health check: MongoDB connection failed: {str(e)}")

        return health_info

    return app


# Create application instance for ASGI servers
app = create_application()
