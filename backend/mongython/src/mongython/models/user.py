"""MongoDB User Model for Chatbot."""

from typing import Optional, Dict, Any, List
from datetime import datetime
from pydantic import BaseModel, Field, EmailStr
from mongython.models.base import BaseDocument
import bcrypt
import logging
from beanie import Document, Link, PydanticObjectId

logger = logging.getLogger(__name__)


class UserCreate(BaseModel):
    """Model for user creation request data."""

    username: str
    name: str
    password: str
    is_admin: bool = False


class User(BaseDocument):
    """Enhanced user model with authentication and metadata."""

    # Basic user data
    username: str = Field(unique=True)
    name: str
    hashed_password: str

    # User metadata
    created_at: datetime = Field(default_factory=datetime.now)
    updated_at: datetime = Field(default_factory=datetime.now)
    last_login: Optional[datetime] = None
    is_active: bool = True
    is_admin: bool = False

    # E2EE Fields
    ed25519_public_key: Optional[str] = None  # Base64 encoded Ed25519 public key
    key_version: int = Field(default=1)  # Keep for potential future use

    # Passphrase Fallback Fields
    argon2_params: Optional[Dict[str, Any]] = (
        None  # Stores salt, iterations, memory, parallelism, etc.
    )
    encrypted_seed_ciphertext: Optional[str] = None  # Base64 encoded encrypted seed

    # Authentication
    auth_token: Optional[str] = None  # LiteLLM Virtual Key

    # Additional metadata
    preferences: Dict[str, Any] = Field(default_factory=dict)
    profile: Dict[str, Any] = Field(default_factory=dict)

    class Settings:
        name = "users"
        indexes = [
            "username",  # Create an index on username field
            ("username", "name"),  # Compound index
        ]

    @classmethod
    async def create_user(
        cls,
        username: str,
        name: str,
        password: str,
        is_admin: bool = False,
    ) -> "User":
        """Create a new user with hashed password."""
        # Hash the password
        salt = bcrypt.gensalt()
        hashed = bcrypt.hashpw(password.encode(), salt)

        now = datetime.now()
        user = cls(
            username=username,
            name=name,
            hashed_password=hashed.decode(),
            is_admin=is_admin,
            created_at=now,
            updated_at=now,
        )
        await user.save()
        return user

    async def verify_password(self, password: str) -> bool:
        """Verify a password against the stored hash."""
        try:
            return bcrypt.checkpw(password.encode(), self.hashed_password.encode())
        except Exception as e:
            logger.error(f"Password verification failed: {e}")
            return False

    async def set_password(self, new_password: str):
        """Set a new password, hashing it before saving."""
        if not new_password or len(new_password) < 8:  # Example: enforce minimum length
            raise ValueError("Password must be at least 8 characters long")
        try:
            salt = bcrypt.gensalt()
            hashed = bcrypt.hashpw(new_password.encode(), salt)
            self.hashed_password = hashed.decode()
            self.updated_at = datetime.now()  # Update timestamp
            await self.save()  # Save the change immediately
            logger.info(f"Password updated for user {self.username}")
        except Exception as e:
            logger.error(f"Failed to set new password for user {self.username}: {e}")
            raise ValueError(f"Failed to set new password: {e}")

    def to_dict(self) -> Dict[str, Any]:
        """Convert user to a dictionary for API responses."""
        return {
            "id": str(self.id),
            "username": self.username,
            "name": self.name,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
            "last_login": self.last_login.isoformat() if self.last_login else None,
            "is_active": self.is_active,
            "is_admin": self.is_admin,
            "has_public_key": bool(self.ed25519_public_key),
            "preferences": self.preferences,
            "profile": self.profile,
        }


class Ed25519PublicKeyUploadRequest(BaseModel):
    public_key_base64: str = Field(
        ..., description="The user's Ed25519 public key, Base64 encoded."
    )
    # key_version: int = Field(1, description="Version of the key format/algorithm") # Add if needed later


class UserLogin(BaseModel):
    username: str
    password: str


# --- Add Public Key Response Model ---
class UserPublicKeyResponse(BaseModel):
    public_key: str = Field(
        ..., description="The user's base64 encoded Ed25519 public key."
    )


# --- End Public Key Response Model ---


# --- Add Passphrase Backup Models ---
class EncryptedSeedRequest(BaseModel):
    argon2_params: Dict[str, Any] = Field(
        ..., description="Parameters used for Argon2 key derivation."
    )
    encrypted_seed_ciphertext: str = Field(
        ...,
        description="The base64 encoded seed, encrypted using key derived from passphrase.",
    )


class EncryptedSeedResponse(BaseModel):
    argon2_params: Dict[str, Any] = Field(
        ..., description="Parameters used for Argon2 key derivation."
    )
    encrypted_seed_ciphertext: str = Field(
        ...,
        description="The base64 encoded seed, encrypted using key derived from passphrase.",
    )


# --- End Passphrase Backup Models ---


class UserBase(BaseModel):
    username: str = Field(..., index=True, unique=True)
    name: Optional[str] = None
    email: Optional[EmailStr] = None
    # We won't store hashed password in this base model
