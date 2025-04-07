"""MongoDB User Model for Chatbot.  """

from typing import Optional, Dict, Any
from datetime import datetime
from pydantic import BaseModel, Field
from mongython.models.base import BaseDocument
import bcrypt
import logging

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
    public_key: Optional[str] = None  # PEM format RSA public key
    key_version: int = Field(default=1)  # For future key rotation support

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
            return bcrypt.checkpw(
                password.encode(),
                self.hashed_password.encode()
            )
        except Exception as e:
            logger.error(f"Password verification failed: {e}")
            return False

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
            "has_public_key": bool(self.public_key),
            "preferences": self.preferences,
            "profile": self.profile,
        }
