"""MongoDB Message Model for Chatbot Conversation."""

from typing import Dict, List, Optional, Any, Literal, Union
from datetime import datetime
from pydantic import BaseModel, Field, UUID4
from beanie import Document, Indexed
import uuid


class MessageMetadata(BaseModel):
    """Metadata for message tracking and analytics."""

    token_count: int = 0
    model_id: Optional[str] = None
    latency_ms: Optional[int] = None
    finish_reason: Optional[str] = None

    # Performance metrics
    tokens_per_second: Optional[float] = None
    cost: Optional[float] = None

    # Raw provider response (optional, for debugging)
    raw_response: Optional[Dict[str, Any]] = None


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
    metadata: MessageMetadata = Field(default_factory=MessageMetadata)

    # For assistant messages, store which model generated it
    model_id: Optional[str] = None

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
            metadata=MessageMetadata(token_count=cls.estimate_token_count(content)),
        )
        await message.save()
        return message

    @classmethod
    async def create_assistant_message(
        cls,
        conversation_id: UUID4,
        content: str,
        model_id: str,
        parent_message_id: UUID4,
        metadata: Optional[MessageMetadata] = None,
    ) -> "Message":
        """Create a new assistant message."""
        if metadata is None:
            metadata = MessageMetadata(
                token_count=cls.estimate_token_count(content), model_id=model_id
            )

        message = cls(
            role="assistant",
            content=content,
            conversation_id=conversation_id,
            parent_message_id=parent_message_id,
            model_id=model_id,
            metadata=metadata,
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
            "metadata": {
                "token_count": self.metadata.token_count,
                "latency_ms": self.metadata.latency_ms,
                "tokens_per_second": self.metadata.tokens_per_second,
                "cost": self.metadata.cost,
                "finish_reason": self.metadata.finish_reason,
            },
        }

    def to_chat_message(self) -> Dict[str, str]:
        """Convert to a chat message format for LLM API calls."""
        return {"role": self.role, "content": self.content}


class TokenWindowState(BaseModel):
    """Tracks the token usage for a conversation window."""

    total_tokens: int = 0
    input_tokens: int = 0
    output_tokens: int = 0
    total_cost: float = 0.0

    def update_from_message(self, message: Message, is_input: bool = None) -> None:
        """Update the token window with tokens from a message."""
        if message.metadata.token_count <= 0:
            return

        token_count = message.metadata.token_count

        # Determine if input or output based on role if not explicitly provided
        if is_input is None:
            is_input = message.role == "user" or message.role == "system"

        # Update token counts
        self.total_tokens += token_count
        if is_input:
            self.input_tokens += token_count
        else:
            self.output_tokens += token_count

        # Update cost if available
        if message.metadata.cost:
            self.total_cost += message.metadata.cost
