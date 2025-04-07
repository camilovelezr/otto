"""MongoDB Message Model for Chatbot Conversation."""

from typing import Dict, Optional, Any, Literal, TYPE_CHECKING, ForwardRef
from datetime import datetime
from pydantic import BaseModel, Field, UUID4
from beanie import Link
import uuid
from mongython.models.base import BaseDocument

if TYPE_CHECKING:
    from mongython.models.user import User
else:
    User = ForwardRef("User")

class TokenWindowState(BaseModel):
    """State tracking for token window management."""
    total_tokens: int = 0
    prompt_tokens: int = 0  # Using OpenAI's naming convention
    completion_tokens: int = 0  # Using OpenAI's naming convention

    def update_from_message(self, message: "Message", is_input: bool = None) -> None:
        """Update token counts from a message."""
        # Get token count from message
        token_count = message.token_count

        # Update total tokens
        self.total_tokens += token_count
        if is_input:
            self.prompt_tokens += token_count
        else:
            self.completion_tokens += token_count

class Message(BaseDocument):
    """Enhanced message model with metadata and encryption support."""

    # Message content and metadata
    role: Literal["user", "assistant", "system"] = "user"
    # content: Optional[str] = None  <- Removed (now handled by renamed encrypted_content)
    # is_encrypted: bool = False <- Removed (always encrypted)
    model_id: Optional[str] = None
    
    # Relationship to user - using proper Link typing
    user: Link[User]

    # Timestamps
    created_at: datetime = Field(default_factory=datetime.now)
    
    # Token usage tracking
    token_usage: Optional[Dict[str, int]] = None
    
    # Additional metadata
    metadata: Dict[str, Any] = Field(default_factory=dict)

    # Relationship to conversation
    conversation_id: UUID4
    parent_message_id: Optional[UUID4] = None  # For threading/replying

    # For assistant messages, store which model generated it
    token_count: int = 0

    # E2EE Fields
    # Stores Base64 encoded encrypted content (IV + Ciphertext) - Renamed from encrypted_content
    content: Optional[str] = None
    # Base64 encoded AES key (encrypted with user's public key)
    encrypted_key: Optional[str] = None
    # Base64 encoded IV for AES-GCM
    iv: Optional[str] = None
    # Base64 encoded authentication tag for AES-GCM
    tag: Optional[str] = None
    # Optional: Store encryption algorithm, IV details if needed separately
    encryption_metadata: Optional[Dict[str, Any]] = None

    class Settings:
        name = "messages"

    @classmethod
    async def create_user_message(
        cls,
        conversation_id: UUID4,
        content: str,
        user: User,
        parent_message_id: Optional[UUID4] = None,
    ) -> "Message":
        """Create a new user message (potentially encrypted)."""
        message = cls(
            role="user",
            conversation_id=conversation_id,
            parent_message_id=parent_message_id,
            user=user,
        )
        # Store encrypted content (field was renamed from encrypted_content)
        # is_encrypted field removed, assuming content is always encrypted
        message.content = content
        # We can't estimate tokens accurately for encrypted content easily
        message.token_count = 0 # Or a placeholder like -1

        await message.save()
        return message

    @classmethod
    async def create_assistant_message(
        cls,
        conversation_id: UUID4,
        content: str,
        model_id: str,
        user: User,
        parent_message_id: UUID4,
        token_count: Optional[int] = None,
    ) -> "Message":
        """Create a new assistant message (potentially encrypted)."""
        message = cls(
            role="assistant",
            conversation_id=conversation_id,
            parent_message_id=parent_message_id,
            model_id=model_id,
            user=user,
        )
        # Store encrypted content (field was renamed from encrypted_content)
        # is_encrypted field removed, assuming content is always encrypted
        message.content = content
        # We can't estimate tokens accurately for encrypted content easily
        message.token_count = token_count if token_count is not None else 0

        await message.save()
        return message

    @staticmethod
    def estimate_token_count(text: str) -> int:
        """Estimate token count using a simple approximation."""
        # Simple approximation: about 4 characters per token for English
        return max(1, len(text) // 4)

    def to_dict(self) -> Dict[str, Any]:
        """Convert message to a dictionary for API responses."""
        data = {
            "id": str(self.id),
            "role": self.role,
            "created_at": self.created_at.isoformat(),
            "model_id": self.model_id,
            "token_count": self.token_count,
            # "is_encrypted": self.is_encrypted, <- Removed
        }
        # Include encrypted content and related E2EE fields
        # Logic based on is_encrypted removed
        data["content"] = self.content # Renamed from encrypted_content
        data["encrypted_key"] = self.encrypted_key
        if self.iv:
            data["iv"] = self.iv
        if self.tag:
            data["tag"] = self.tag
        return data

    def to_chat_message(self) -> Dict[str, str]:
        """Convert to a chat message format for LLM API calls.
           Assumes content is decrypted before calling this.
           If called on an encrypted message without prior decryption, content might be None.
        """
        # Ensure content is not None before returning.
        # This method should ideally only be called on decrypted messages.
        # Checks for is_encrypted removed as it's always true now.
        # The logic now relies solely on self.content being populated (via decryption).
        if self.content is None:
             # This indicates an issue - trying to format an encrypted message for LLM
             # without prior decryption, or content was genuinely null (which shouldn't happen).
             # Handle appropriately.
             raise ValueError("Cannot format message for LLM: content is None (message likely not decrypted).")

        return {"role": self.role, "content": self.content} # self.content should not be None here
