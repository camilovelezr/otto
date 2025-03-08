"""MongoDB Conversation Model for Chatbot."""

import uuid
from typing import Dict, List, Optional, Any, Annotated
from datetime import datetime
from pydantic import BaseModel, Field, UUID4
from beanie import Document, Link, Indexed
from mongython.models.user import User
from mongython.models.message import Message, TokenWindowState


class Conversation(Document):
    """Enhanced conversation model with message tracking and metadata."""

    # Unique identifier
    id: UUID4 = Field(default_factory=uuid.uuid4)

    # Relationship to user
    user: Link[User]

    # Basic conversation data
    title: Optional[str] = None
    tags: List[str] = Field(default_factory=list)

    # Timestamps
    created_at: datetime = Field(default_factory=datetime.now)
    updated_at: Annotated[datetime, Indexed()] = Field(default_factory=datetime.now)

    # Token tracking
    token_window: TokenWindowState = Field(default_factory=TokenWindowState)

    # Additional metadata
    detected_topics: List[str] = Field(
        default_factory=list
    )  # Topics detected from messages
    summary: Optional[str] = None  # AI-generated summary of conversation

    class Settings:
        name = "conversations"

    @classmethod
    async def create_initial(cls, user_id: str) -> "Conversation":
        """Create a new conversation."""
        user = await User.get(user_id)
        if not user:
            raise ValueError("User not found")

        conversation = cls(
            user=user,
            created_at=datetime.now(),
            updated_at=datetime.now(),
        )
        await conversation.save()
        return conversation

    async def add_user_message(
        self,
        content: str,
        parent_message_id: Optional[UUID4] = None,
    ) -> Message:
        """Add a user message to the conversation."""
        # Update conversation timestamp
        self.updated_at = datetime.now()
        await self.save()

        # Create the message
        message = await Message.create_user_message(
            conversation_id=self.id,
            content=content,
            parent_message_id=parent_message_id,
        )

        # Update token window
        self.token_window.update_from_message(message, is_input=True)
        await self.save()

        return message

    async def add_assistant_message(
        self,
        content: str,
        model_id: str,
        parent_message_id: UUID4,
        token_count: Optional[int] = None,
    ) -> Message:
        """Add an assistant message to the conversation."""
        # Create the message
        message = await Message.create_assistant_message(
            conversation_id=self.id,
            content=content,
            model_id=model_id,
            parent_message_id=parent_message_id,
            token_count=token_count,
        )

        # Update token window
        self.token_window.update_from_message(message, is_input=False)
        await self.save()

        return message

    async def get_messages(self) -> List[Message]:
        """Get all messages in the conversation."""
        return (
            await Message.find(Message.conversation_id == self.id)
            .sort("+created_at")
            .to_list()
        )

    async def get_messages_for_model(
        self, model_id: Optional[str] = None
    ) -> List[Dict[str, str]]:
        """Get messages in a format suitable for sending to an LLM API."""
        messages = await self.get_messages()

        # Filter by model if requested
        if model_id:
            filtered_messages = []
            for message in messages:
                if message.role == "user" or message.model_id == model_id:
                    filtered_messages.append(message)
            messages = filtered_messages

        # Convert to chat message format
        return [message.to_chat_message() for message in messages]

    async def get_message_thread(self, message_id: UUID4) -> List[Message]:
        """Get a thread of messages starting from a specific message."""
        # Get the original message
        message = await Message.find_one(
            (Message.id == message_id) & (Message.conversation_id == self.id)
        )

        if not message:
            return []

        # Build the thread by collecting parent messages
        thread = [message]
        current_id = message.parent_message_id

        while current_id:
            parent = await Message.find_one(
                (Message.id == current_id) & (Message.conversation_id == self.id)
            )
            if not parent:
                break

            thread.insert(0, parent)
            current_id = parent.parent_message_id

        return thread

    def to_dict(self) -> Dict[str, Any]:
        """Convert conversation to a dictionary for API responses."""
        return {
            "id": str(self.id),
            "title": self.title,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
            "token_window": {
                "total_tokens": self.token_window.total_tokens,
                "input_tokens": self.token_window.input_tokens,
                "output_tokens": self.token_window.output_tokens,
                "total_cost": self.token_window.total_cost,
            },
            "tags": self.tags,
            "detected_topics": self.detected_topics,
            "summary": self.summary,
        }
