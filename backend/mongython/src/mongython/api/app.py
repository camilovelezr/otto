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

    # LiteLLM passthrough - Use the global LITELLM_URL
    @app.api_route(
        "/litellm{path:path}",
        methods=["GET", "POST", "PUT", "DELETE"],
        tags=["litellm"],
    )
    async def litellm_passthrough(request: Request, path: str):
        """Passthrough endpoint for LiteLLM service."""
        client = httpx.AsyncClient(base_url=LITELLM_URL)

        try:
            # Get request details
            url = f"{path}"

            # Forward most headers, but add or modify specific ones for LiteLLM
            headers = {
                key: value
                for key, value in request.headers.items()
                if key.lower()
                not in (
                    "host",
                    "content-length",
                    "authorization",
                )  # Don't forward any existing auth header
            }

            # Get username from headers for authentication
            username = request.headers.get("X-Username")
            if not username:
                raise HTTPException(
                    status_code=401, detail="X-Username header is required"
                )

            # Get user document to access their auth token
            user = await User.find_one(User.username == username)
            if not user or not user.auth_token:
                raise HTTPException(
                    status_code=401, detail="User not found or no auth token available"
                )

            # Use the user's auth token for LiteLLM
            headers["Authorization"] = f"Bearer {user.auth_token}"
            logger.debug(f"Using auth token for user: {username}")

            # Get the request body if it exists
            body = await request.body()

            # Log the request (but omit sensitive data)
            logger.info(f"LiteLLM passthrough: {request.method} {url}")

            # Make the request to the LiteLLM service
            response = await client.request(
                method=request.method,
                url=url,
                headers=headers,
                content=body,
                timeout=None,
            )

            # Get the response content and headers
            content = response.content
            response_headers = {
                key: value
                for key, value in response.headers.items()
                if key.lower() not in ("transfer-encoding")
            }

            # Return a streaming response if the original response is streaming
            if "content-type" in response_headers and "stream" in response_headers.get(
                "content-type", ""
            ):
                return StreamingResponse(
                    content=response.aiter_bytes(),
                    status_code=response.status_code,
                    headers=response_headers,
                )

            # Regular response
            return Response(
                content=content,
                status_code=response.status_code,
                headers=response_headers,
            )

        except httpx.RequestError as e:
            logger.error(f"Error connecting to LiteLLM service: {str(e)}")
            raise HTTPException(
                status_code=503, detail=f"Error connecting to LiteLLM service: {str(e)}"
            )
        finally:
            await client.aclose()

    return app


# Create application instance for ASGI servers
app = create_application()
