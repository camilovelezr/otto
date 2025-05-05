"""FastAPI Users API."""

import logging
import asyncio
import os
from typing import Optional, Dict, Any
import httpx
import base64

from fastapi import (
    APIRouter,
    Body,
    HTTPException,
    status,
    Response,
    Request,
    Depends,  # Added Depends
    Header,
)
from pydantic import BaseModel, Field  # Added BaseModel and Field
from fastapi.responses import JSONResponse
from beanie import PydanticObjectId

from mongython.models.user import (
    User,
    UserCreate,
    UserLogin,
    Ed25519PublicKeyUploadRequest,
    UserPublicKeyResponse,
    EncryptedSeedRequest,
    EncryptedSeedResponse,
)
from mongython.api.errors import ErrorResponse

# Import encryption utils to validate the key format (optional but good practice)
from mongython.utils.encryption import load_public_key_from_pem
from datetime import datetime  # Keep datetime
from mongython.models.conversation import Conversation
from mongython.models.message import Message
from mongython.utils.encryption import server_encryption
from mongython.utils.server_encryption import (
    server_encryption as server_encryption_utils,
)

# Configure logging
logger = logging.getLogger(__name__)

# Load environment variables
LITELLM_URL = os.getenv("LITELLM_URL", "http://localhost:4000")
LITELLM_MASTER_KEY = os.getenv("LITELLM_MASTER_KEY")

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


# --- User CRUD Operations ---


class UserResponse(BaseModel):
    """Response model for user data, excluding sensitive fields."""

    id: str
    username: str
    name: str
    created_at: datetime
    updated_at: datetime
    has_public_key: bool
    key_version: int
    auth_token: Optional[str] = None


async def generate_litellm_key(username: str) -> str:
    """Generate a virtual key for the user using LiteLLM's key generation endpoint."""
    try:
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{LITELLM_URL}/key/generate",
                headers={
                    "Authorization": f"Bearer {LITELLM_MASTER_KEY}",
                    "Content-Type": "application/json",
                },
                json={"user_id": username, "metadata": {"user": username}},
                timeout=10.0,
            )

            if response.status_code != 200:
                logger.error(f"Failed to generate LiteLLM key: {response.text}")
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail="Failed to generate LiteLLM key",
                )

            data = response.json()
            return data["key"]
    except Exception as e:
        logger.error(f"Error generating LiteLLM key: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error generating LiteLLM key: {str(e)}",
        )


@router.post(
    "/create",
    status_code=status.HTTP_201_CREATED,
    response_model=UserResponse,
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

        # Create user with unpacked arguments
        logger.info(f"Creating user with username: {user.username}")
        new_user_doc = await User.create_user(
            username=user.username, password=user.password, name=user.name
        )

        # Generate and set the LiteLLM virtual key
        auth_token = await generate_litellm_key(user.username)
        new_user_doc.auth_token = auth_token
        await new_user_doc.save()

        # Return the user details using the response model
        return UserResponse(
            id=str(new_user_doc.id),
            username=new_user_doc.username,
            name=new_user_doc.name,
            created_at=new_user_doc.created_at,
            updated_at=new_user_doc.updated_at,
            has_public_key=new_user_doc.ed25519_public_key is not None,
            key_version=new_user_doc.key_version,
            auth_token=new_user_doc.auth_token,
        )

    except HTTPException:
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
                "Suggestion: Make sure MongoDB is running on the configured host and port"
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
        else:
            logger.error(
                f"Error creating user {user.username}: {str(e)}", exc_info=True
            )
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Internal server error while creating user. Please try again later.",
            )


# --- Public Key Upload Endpoint (Modified for Ed25519) ---

# Remove old request model definition if it exists elsewhere
# class PublicKeyUploadRequest(BaseModel):
#    public_key_pem: str


@router.post(
    "/me/public-key",
    status_code=status.HTTP_200_OK,
    # Use standard response model? Or custom success message?
    response_model=Dict[str, str],
    summary="Upload user's Ed25519 public key",
    description="Uploads the base64 encoded Ed25519 public key for the authenticated user.",
    responses={
        400: {"model": ErrorResponse, "description": "Invalid key format or data"},
        401: {"model": ErrorResponse, "description": "Authentication required"},
    },
)
async def upload_ed25519_public_key(
    key_data: Ed25519PublicKeyUploadRequest,
    current_user: User = Depends(get_current_user),
):
    """
    Allows the authenticated user to upload their Ed25519 public key.
    """
    try:
        # Decode the key from base64
        key_bytes = base64.b64decode(key_data.public_key_base64)

        # Validate key length (Ed25519 public key is 32 bytes)
        if len(key_bytes) != 32:
            raise ValueError("Decoded public key must be 32 bytes long.")
        logger.info(
            f"Ed25519 public key format validated for user {current_user.username}"
        )

        # Update the user document with the base64 encoded key
        current_user.ed25519_public_key = key_data.public_key_base64
        # Optionally update key_version if needed, or handle in client/seed logic
        # current_user.key_version = current_user.key_version + 1
        await current_user.save()
        logger.info(
            f"Ed25519 public key stored/updated for user {current_user.username}"
        )

        return {
            "status": "success",
            "message": "Ed25519 public key stored successfully",
        }

    except HTTPException:
        raise  # Re-raise validation errors
    except Exception as e:
        logger.error(
            f"Error uploading Ed25519 key for {current_user.username}: {e}",
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error while storing public key.",
        )


# Remove or comment out the duplicate route definition if present
# @router.post(\"/me/public-key\", ...)
# async def update_public_key(...): ...

# --- Endpoints like /list, /{user_name}, /delete, /verify remain the same ---


# --- NEW: Endpoint to get a user's public key ---
@router.get(
    "/{username}/public-key",
    response_model=UserPublicKeyResponse,
    summary="Get user's public key",
    description="Retrieves the base64 encoded Ed25519 public key for a given username.",
    responses={
        401: {"model": ErrorResponse, "description": "Authentication required"},
        404: {
            "model": ErrorResponse,
            "description": "User not found or key not available",
        },
    },
)
async def get_user_public_key(
    username: str,
    current_user: User = Depends(get_current_user),  # Require auth to call this
):
    """Fetches the public key for the specified user."""
    logger.info(f"User {current_user.username} requesting public key for {username}")
    target_user = await User.find_one(User.username == username)

    if not target_user:
        logger.warning(f"Public key request failed: User {username} not found.")
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    if not target_user.ed25519_public_key:
        logger.warning(
            f"Public key request failed: User {username} has no public key registered."
        )
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Public key not found for this user",
        )

    logger.info(f"Returning public key for user {username}")
    return UserPublicKeyResponse(public_key=target_user.ed25519_public_key)


# --- NEW: Passphrase Fallback Endpoints ---


@router.post(
    "/me/encrypted-seed",
    status_code=status.HTTP_200_OK,
    response_model=Dict[str, str],
    summary="Store encrypted seed for passphrase fallback",
    description="Stores the Argon2 parameters and the encrypted seed ciphertext for the authenticated user.",
    responses={
        400: {"model": ErrorResponse, "description": "Invalid data"},
        401: {"model": ErrorResponse, "description": "Authentication required"},
    },
)
async def store_encrypted_seed(
    seed_data: EncryptedSeedRequest,  # Use the Pydantic model for request body
    current_user: User = Depends(get_current_user),
):
    """Stores the encrypted seed and Argon2 parameters for the user."""
    try:
        # Basic validation (e.g., ensure ciphertext is not empty)
        if not seed_data.encrypted_seed_ciphertext or not seed_data.argon2_params:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Missing encrypted seed ciphertext or Argon2 parameters.",
            )

        current_user.argon2_params = seed_data.argon2_params
        current_user.encrypted_seed_ciphertext = seed_data.encrypted_seed_ciphertext
        current_user.updated_at = datetime.now()  # Update timestamp
        await current_user.save()
        logger.info(f"Stored encrypted seed backup for user {current_user.username}")
        return {"status": "success", "message": "Encrypted seed stored successfully"}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(
            f"Error storing encrypted seed for {current_user.username}: {e}",
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error while storing encrypted seed.",
        )


@router.get(
    "/me/encrypted-seed",
    response_model=EncryptedSeedResponse,
    summary="Retrieve encrypted seed for passphrase fallback",
    description="Retrieves the stored Argon2 parameters and encrypted seed ciphertext for the authenticated user.",
    responses={
        401: {"model": ErrorResponse, "description": "Authentication required"},
        404: {
            "model": ErrorResponse,
            "description": "Encrypted seed not found for user",
        },
    },
)
async def get_encrypted_seed(
    current_user: User = Depends(get_current_user),
):
    """Retrieves the stored encrypted seed and Argon2 parameters."""
    if not current_user.encrypted_seed_ciphertext or not current_user.argon2_params:
        logger.warning(
            f"Encrypted seed requested but not found for user {current_user.username}"
        )
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No encrypted seed backup found for this user.",
        )

    logger.info(f"Returning encrypted seed backup for user {current_user.username}")
    return EncryptedSeedResponse(
        argon2_params=current_user.argon2_params,
        encrypted_seed_ciphertext=current_user.encrypted_seed_ciphertext,
    )


# --- Admin Endpoints ---


@router.delete("/admin/all", response_model=dict)
async def admin_delete_all_users():
    """Admin endpoint to delete all users. No auth required - meant for local admin use."""
    try:
        # Find all users
        users = await User.find_all().to_list()

        # For each user, delete their conversations first
        total_conversations = 0
        total_messages = 0

        for user in users:
            # Delete conversations and messages
            conversations = await Conversation.find(
                Conversation.user.id == user.id
            ).to_list()
            total_conversations += len(conversations)

            for conversation in conversations:
                messages = await Message.find(
                    Message.conversation_id == conversation.id
                ).to_list()
                total_messages += len(messages)
                for message in messages:
                    await message.delete()
                await conversation.delete()

            # Delete the user
            await user.delete()

        return {
            "status": "success",
            "users_deleted": len(users),
            "conversations_deleted": total_conversations,
            "messages_deleted": total_messages,
        }
    except Exception as e:
        logger.error(f"Admin error deleting all users: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error deleting all users: {str(e)}",
        )


@router.delete("/admin/{username}", response_model=dict)
async def admin_delete_user(username: str):
    """Admin endpoint to delete a specific user and all their data. No auth required - meant for local admin use."""
    try:
        # Find the user
        user = await User.find_one(User.username == username)
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"User {username} not found",
            )

        # Delete conversations and messages
        conversations = await Conversation.find(
            Conversation.user.id == user.id
        ).to_list()
        total_messages = 0

        for conversation in conversations:
            messages = await Message.find(
                Message.conversation_id == conversation.id
            ).to_list()
            total_messages += len(messages)
            for message in messages:
                await message.delete()
            await conversation.delete()

        # Delete the user
        await user.delete()

        return {
            "status": "success",
            "username": username,
            "conversations_deleted": len(conversations),
            "messages_deleted": total_messages,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Admin error deleting user {username}: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error deleting user {username}: {str(e)}",
        )


class ServerPublicKeyResponse(BaseModel):
    public_key: str


@router.get("/server-public-key", response_model=ServerPublicKeyResponse)
async def get_server_public_key():
    """Get the server's public key for client-side encryption."""
    try:
        return {"public_key": server_encryption_utils.get_public_key_pem()}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to get server public key: {str(e)}",
        )


class LoginRequest(BaseModel):
    """Request model for user login."""

    username: str
    password: str


@router.post(
    "/login",
    response_model=UserResponse,
    summary="Login user",
    description="Authenticates a user with username and password",
    responses={
        400: {"model": ErrorResponse, "description": "Bad request"},
        401: {"model": ErrorResponse, "description": "Invalid credentials"},
    },
)
async def login_user(login_data: LoginRequest):
    """Login endpoint for user authentication."""
    try:
        # Find user by username
        user = await User.find_one(User.username == login_data.username)
        if not user:
            logger.warning(
                f"Login attempt with non-existent username: {login_data.username}"
            )
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid username or password",
            )

        # Verify password
        if not await user.verify_password(login_data.password):
            logger.warning(f"Failed login attempt for user: {login_data.username}")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid username or password",
            )

        # Generate new auth token
        auth_token = await generate_litellm_key(user.username)
        user.auth_token = auth_token
        await user.save()

        logger.info(f"Successful login for user: {login_data.username}")

        # Return user data with token
        return UserResponse(
            id=str(user.id),
            username=user.username,
            name=user.name,
            created_at=user.created_at,
            updated_at=user.updated_at,
            has_public_key=user.ed25519_public_key is not None,
            key_version=user.key_version,
            auth_token=user.auth_token,
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(
            f"Error during login for user {login_data.username}: {str(e)}",
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error during login",
        )


class UserPasswordUpdate(BaseModel):
    """Request model for updating user's password."""

    current_password: str = Field(..., description="Current password for verification")
    new_password: str = Field(
        ..., min_length=8, description="New password (min 8 characters)"
    )


@router.put(
    "/me/password",
    response_model=Dict[str, str],
    summary="Update user's password",
    description="Updates the password for the authenticated user after verifying current password.",
    responses={
        400: {
            "model": ErrorResponse,
            "description": "Bad request (e.g., weak password)",
        },
        401: {
            "model": ErrorResponse,
            "description": "Authentication required or invalid current password",
        },
    },
)
async def update_user_password(
    update_data: UserPasswordUpdate,
    current_user: User = Depends(get_current_user),
) -> Dict[str, str]:
    """Updates the authenticated user's password after verifying the current password."""
    try:
        # Verify current password
        if not await current_user.verify_password(update_data.current_password):
            logger.warning(
                f"Failed password update attempt for user {current_user.username}: incorrect current password"
            )
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Current password is incorrect",
            )

        # Set the new password
        await current_user.set_password(update_data.new_password)
        logger.info(f"Password updated successfully for user {current_user.username}")
        return {"status": "success", "message": "Password updated successfully"}

    except ValueError as e:
        logger.warning(f"Invalid new password for user {current_user.username}: {e}")
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e),
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error(
            f"Error updating password for user {current_user.username}: {e}",
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update password",
        )
