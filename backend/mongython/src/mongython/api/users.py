"""FastAPI Users API."""

import logging
import asyncio
import os

from fastapi import (
    APIRouter,
    Body,
    HTTPException,
    status,
    Response,
    Request,
)

from mongython.models.user import User, UserCreate
from mongython.api.errors import ErrorResponse

# Configure logging
logger = logging.getLogger(__name__)


# Create a router
router = APIRouter(
    prefix="/users",
    tags=["users"],
    responses={500: {"model": ErrorResponse, "description": "Internal server error"}},
)


async def get_current_user(request: Request) -> User:
    """
    Retrieve the current authenticated user from the request.

    This function acts as a dependency for endpoints that require authentication.
    It extracts the username from the X-Username header and retrieves the corresponding user.

    Args:
        request: The FastAPI request object

    Returns:
        User: The authenticated user object

    Raises:
        HTTPException: If no username is provided or the user is not found
    """
    username = request.headers.get("X-Username")

    if not username:
        logger.warning("Authentication attempt without username")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user = await User.find_one(User.username == username)
    if not user:
        logger.warning(f"Authentication attempt with invalid username: {username}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    logger.info(f"User authenticated: {username}")
    return user


@router.post(
    "/create",
    status_code=status.HTTP_201_CREATED,
    summary="Create a new user",
    description="Creates a new user with the provided information",
    response_description="The created user",
    responses={400: {"model": ErrorResponse, "description": "Bad request"}},
)
async def create_user(user: UserCreate):
    try:
        # Check if username already exists
        existing_user = await User.find_one(User.username == user.username)
        if existing_user:
            logger.warning(f"Attempted to create duplicate username: {user.username}")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already exists",
            )

        # Create user (without logging password)
        logger.info(f"Creating user with username: {user.username}")
        created_user = await User.create_user(user)
        await created_user.insert()
        logger.info(f"User created: {user.username}")

        # Return the user without the password field
        user_dict = created_user.model_dump()
        user_dict["password"] = "[REDACTED]"
        return user_dict
    except HTTPException:
        # Re-raise HTTP exceptions
        raise
    except Exception as e:
        # Handle specific database-related errors
        if "All connection attempts failed" in str(
            e
        ) or "ServerSelectionTimeoutError" in str(type(e)):
            error_message = "Unable to connect to database. Please check if MongoDB service is running."
            logger.error(
                f"Database connection error creating user {user.username}: {str(e)}"
            )
            logger.error(
                f"Suggestion: Make sure MongoDB is running on the configured host and port"
            )
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=error_message,
            )
        elif "Could not connect to LiteLLM service" in str(e):
            litellm_url = os.getenv("LITELLM_URL", "http://localhost:4000")
            error_message = f"Unable to connect to LiteLLM service at {litellm_url}. Please check if the service is running."
            logger.error(
                f"LiteLLM connection error creating user {user.username}: {str(e)}"
            )
            logger.error(
                f"Suggestion: Make sure the LiteLLM service is running and accessible at {litellm_url}"
            )
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=error_message,
            )
        elif "duplicate key error" in str(e).lower():
            logger.warning(
                f"Duplicate key error creating user {user.username}: {str(e)}"
            )
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already exists",
            )
        else:
            # Log error without exposing sensitive information
            logger.error(
                f"Error creating user {user.username}: {str(e)}", exc_info=True
            )
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Internal server error while creating user. Please try again later.",
            )


@router.get(
    "/list",
    summary="Get all users",
    description="Retrieves a list of all users",
    response_description="List of users",
)
async def get_users():
    try:
        users = await User.find_all().to_list()
        logger.info(f"Retrieved {len(users)} users")
        return users
    except Exception as e:
        logger.error(f"Error retrieving users: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error retrieving users",
        )


@router.get(
    "/{user_name}",
    summary="Get user by username",
    description="Retrieves a user by their username",
    response_description="User details",
    responses={
        404: {"model": ErrorResponse, "description": "User not found"},
    },
)
async def get_user(user_name: str):
    try:
        user = await User.find_one(User.username == user_name)
        if not user:
            logger.warning(f"User not found: {user_name}")
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="User not found"
            )
        logger.info(f"Retrieved user: {user_name}")
        return user
    except Exception as e:
        if not isinstance(e, HTTPException):
            logger.error(f"Error retrieving user {user_name}: {e}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Error retrieving user",
            )
        raise


@router.delete(
    "/{user_name}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a user",
    description="Deletes a user by their username",
    responses={
        404: {"model": ErrorResponse, "description": "User not found"},
    },
)
async def delete_user(user_name: str):
    if user_name == "all":
        try:
            users = await User.find_all().to_list()
            for user in users:
                await user.delete()
            logger.info(f"Successfully deleted all users: {len(users)} users removed")
            return Response(status_code=status.HTTP_204_NO_CONTENT)
        except Exception as e:
            logger.error(f"Error deleting all users: {e}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Error deleting all users: {str(e)}",
            )
    else:
        try:
            user = await User.find_one(User.username == user_name)
            if not user:
                logger.warning(f"Attempted to delete non-existent user: {user_name}")
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND, detail="User not found"
                )
            await user.delete()
            logger.info(f"User deleted: {user_name}")
            return Response(status_code=status.HTTP_204_NO_CONTENT)
        except Exception as e:
            if not isinstance(e, HTTPException):
                logger.error(f"Error deleting user {user_name}: {e}")
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="Error deleting user",
                )
            raise


@router.post(
    "/{user_name}/verify",
    summary="Verify user credentials",
    description="Verifies a user's password",
    response_description="Verification result",
    responses={
        401: {"model": ErrorResponse, "description": "Invalid credentials"},
        404: {"model": ErrorResponse, "description": "User not found"},
    },
)
async def verify_user(
    user_name: str, password: str = Body(..., description="User password")
):
    try:
        user = await User.find_one(User.username == user_name)
        if not user:
            # Add a small delay to prevent timing attacks
            await asyncio.sleep(0.5)
            logger.warning(f"Verification attempt for non-existent user: {user_name}")
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="User not found"
            )

        if not user.verify_password(password):
            logger.warning(f"Failed login attempt for user: {user_name}")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid password"
            )

        logger.info(f"User verified successfully: {user_name}")
        return {"status": "success", "message": "User verified successfully"}
    except Exception as e:
        if not isinstance(e, HTTPException):
            logger.error(f"Error during user verification for {user_name}: {e}")
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Error during verification",
            )
        raise
