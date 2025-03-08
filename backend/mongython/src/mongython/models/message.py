"""MongoDB Message Model for Chatbot Conversation."""

from typing import Dict, Optional, Any, Literal
from datetime import datetime
from pydantic import BaseModel, Field, UUID4
from beanie import Document
import uuid


class Message(Document):
    """Unified message model for both user and assistant messages."""

    # Core message data
    id: UUID4 = Field(default_factory=uuid.uuid4)
    role: Literal["user", "assistant", "system"] = "user"
    content: str

    # Relationship to conversation
    conversation_id: UUID4
    parent_message_id: Optional[UUID4] = None  # For threading/replying

    # Message metadata
    created_at: datetime = Field(default_factory=datetime.now)

    # For assistant messages, store which model generated it
    model_id: Optional[str] = None
    token_count: int = 0

    class Settings:
        name = "messages"

    @classmethod
    async def create_user_message(
        cls,
        conversation_id: UUID4,
        content: str,
        parent_message_id: Optional[UUID4] = None,
    ) -> "Message":
        """Create a new user message."""
        message = cls(
            role="user",
            content=content,
            conversation_id=conversation_id,
            parent_message_id=parent_message_id,
        )
        message.token_count = cls.estimate_token_count(content)
        await message.save()
        return message

    @classmethod
    async def create_assistant_message(
        cls,
        conversation_id: UUID4,
        content: str,
        model_id: str,
        parent_message_id: UUID4,
        token_count: Optional[int] = None,
    ) -> "Message":
        """Create a new assistant message."""

        message = cls(
            role="assistant",
            content=content,
            conversation_id=conversation_id,
            parent_message_id=parent_message_id,
            model_id=model_id,
            token_count=token_count,
        )
        await message.save()
        return message

    @staticmethod
    def estimate_token_count(text: str) -> int:
        """Estimate token count using a simple approximation."""
        # Simple approximation: about 4 characters per token for English
        return max(1, len(text) // 4)

    def to_dict(self) -> Dict[str, Any]:
        """Convert message to a dictionary for API responses."""
        return {
            "id": str(self.id),
            "role": self.role,
            "content": self.content,
            "created_at": self.created_at.isoformat(),
            "model_id": self.model_id,
            "token_count": self.token_count,
        }

    def to_chat_message(self) -> Dict[str, str]:
        """Convert to a chat message format for LLM API calls."""
        return {"role": self.role, "content": self.content}


class TokenWindowState(BaseModel):
    """Tracks the token usage for a conversation window."""

    total_tokens: int = 0
    input_tokens: int = 0
    output_tokens: int = 0

    def update_from_message(self, message: Message, is_input: bool = None) -> None:
        """Update the token window with tokens from a message."""
        if message.token_count <= 0:
            return

        token_count = message.token_count

        # Determine if input or output based on role if not explicitly provided
        # if is_input is None:
        is_input = message.role == "user" or message.role == "system"

        # Update token counts
        self.total_tokens += token_count
        if is_input:
            self.input_tokens += token_count
        else:
            self.output_tokens += token_count
