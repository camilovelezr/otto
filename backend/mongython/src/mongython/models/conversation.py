"""MongoDB Conversation Model for Chatbot."""

from typing import Dict, List, Optional, Any, Union, Annotated
from datetime import datetime
from pydantic import BaseModel, Field, UUID4
from beanie import Document, Indexed, Link
import uuid

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

    async def add_user_message(self, content: str) -> Message:
        """Add a user message to the conversation."""
        # Update conversation timestamp
        self.updated_at = datetime.now()
        await self.save()

        # Create the message
        message = await Message.create_user_message(
            conversation_id=self.id, content=content
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
        metadata: Optional[Dict[str, Any]] = None,
    ) -> Message:
        """Add an assistant (AI) message to the conversation."""
        # Update conversation timestamp
        self.updated_at = datetime.now()
        await self.save()

        # Create message metadata if provided
        message_metadata = None
        if metadata:
            from mongython.models.message import MessageMetadata

            message_metadata = MessageMetadata(**metadata)

        # Create the message
        message = await Message.create_assistant_message(
            conversation_id=self.id,
            content=content,
            model_id=model_id,
            parent_message_id=parent_message_id,
            metadata=message_metadata,
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

    @classmethod
    async def migrate_from_old_format(cls, conversation_id: str) -> "Conversation":
        """
        Migrate a conversation from the old format to the new format.

        This is a helper method for transitioning from the old storage format
        to the new Message-based format.
        """
        from mongython.models.conversation_old import Conversation as OldConversation

        # Find the old conversation
        old_conversation = await OldConversation.get(conversation_id)
        if not old_conversation:
            raise ValueError(f"Old conversation with ID {conversation_id} not found")

        # Create new conversation with same metadata
        new_conversation = cls(
            id=uuid.UUID(conversation_id),
            user=old_conversation.user,
            title=old_conversation.title,
            created_at=old_conversation.created_at,
            updated_at=old_conversation.updated_at,
        )
        await new_conversation.save()

        # Convert old messages to new format
        parent_message_id = None
        for old_message in old_conversation.messages:
            if isinstance(old_message, dict) and old_message.get("role") == "user":
                # User message
                message = await Message.create_user_message(
                    conversation_id=new_conversation.id,
                    content=old_message.get("content", ""),
                    parent_message_id=parent_message_id,
                )
                parent_message_id = message.id

                # Update token window
                new_conversation.token_window.update_from_message(
                    message, is_input=True
                )

            elif hasattr(old_message, "choices") and hasattr(
                old_message.choices[0], "message"
            ):
                # Assistant message (from ChatCompletion)
                content = old_message.choices[0].message.content
                model_id = getattr(old_message, "model", "unknown")

                message = await Message.create_assistant_message(
                    conversation_id=new_conversation.id,
                    content=content,
                    model_id=model_id,
                    parent_message_id=parent_message_id,
                )
                parent_message_id = message.id

                # Update token window
                new_conversation.token_window.update_from_message(
                    message, is_input=False
                )

        # Save updated token window
        await new_conversation.save()
        return new_conversation
