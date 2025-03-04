"""Error handling for the API."""

import logging
import traceback
import sys
from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from fastapi.exceptions import RequestValidationError
from pymongo.errors import ServerSelectionTimeoutError, ConnectionFailure

logger = logging.getLogger(__name__)


# Custom error response model
class ErrorResponse(BaseModel):
    """Standard error response model."""

    detail: str
    error_code: str = "INTERNAL_ERROR"
    suggestion: str = ""


# Middleware to catch and properly log unhandled exceptions
async def http_exception_handler(request: Request, exc: HTTPException):
    """Global exception handler for HTTP exceptions."""
    # Get the request path
    path = request.url.path

    # Create error code based on status code
    error_code = f"HTTP_{exc.status_code}"

    # Default suggestion for common errors
    suggestion = ""
    if exc.status_code == 503:
        suggestion = "Try again later or check if backend services are running"
    elif exc.status_code == 401:
        suggestion = "Please login with valid credentials"
    elif exc.status_code == 403:
        suggestion = "You don't have permission to access this resource"
    elif exc.status_code == 404:
        suggestion = "Check the URL and try again"

    # Enhanced logging based on error severity
    if exc.status_code >= 500:
        logger.error(f"HTTP error: {exc.status_code} - {exc.detail} - Path: {path}")
    elif exc.status_code >= 400:
        logger.warning(f"HTTP error: {exc.status_code} - {exc.detail} - Path: {path}")
    else:
        logger.info(f"HTTP status: {exc.status_code} - {exc.detail} - Path: {path}")

    # Include headers if specified
    headers = getattr(exc, "headers", None)

    return JSONResponse(
        status_code=exc.status_code,
        content={
            "detail": exc.detail,
            "error_code": error_code,
            "suggestion": suggestion,
        },
        headers=headers,
    )


async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Handle validation errors and sanitize sensitive information.

    This handler prevents sensitive information like passwords from being
    included in the error responses.
    """
    # Convert errors to a sanitized list
    sanitized_errors = []

    for error in exc.errors():
        # Create a sanitized copy of the error
        sanitized_error = error.copy()

        # If the error is about a password field, don't include the input value
        if any(
            "password" in str(loc_part).lower() for loc_part in error.get("loc", [])
        ):
            if "input" in sanitized_error:
                sanitized_error["input"] = "[REDACTED]"

        sanitized_errors.append(sanitized_error)

    # Log validation error with request path
    path = request.url.path
    logger.warning(f"Validation error: {sanitized_errors} - Path: {path}")

    # Return a sanitized response
    return JSONResponse(
        status_code=422,
        content={
            "detail": sanitized_errors,
            "error_code": "VALIDATION_ERROR",
            "suggestion": "Please check your input data and try again",
        },
    )


# Custom exception handler for database-related errors
async def handle_db_exception(request: Request, exc: Exception):
    """Handle database-related exceptions."""
    path = request.url.path
    error_type = type(exc).__name__

    # Log the full exception with traceback
    logger.error(f"Database error in {path}: {str(exc)}")
    logger.error("".join(traceback.format_exception(type(exc), exc, exc.__traceback__)))

    # Create user-friendly message
    detail = "Database connection error"
    suggestion = "Please ensure MongoDB is running and properly configured"

    if isinstance(exc, ServerSelectionTimeoutError):
        detail = "Unable to connect to MongoDB server"
        suggestion = "Check if MongoDB service is running"
    elif isinstance(exc, ConnectionFailure):
        detail = "MongoDB connection lost"
        suggestion = (
            "The connection to MongoDB was interrupted. Please try again later."
        )

    # Return a user-friendly response
    return JSONResponse(
        status_code=503,  # Service Unavailable
        content={
            "detail": detail,
            "error_code": "DATABASE_CONNECTION_ERROR",
            "suggestion": suggestion,
        },
    )
