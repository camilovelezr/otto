"""MongoDB Conversation Model for Chatbot."""

import uuid
from typing import Dict, List, Optional, Any, Annotated
from datetime import datetime
from pydantic import BaseModel, Field, UUID4
from beanie import Link, Indexed
import base64
from mongython.utils.encryption import generate_aes_key, encrypt_with_rsa_public_key, load_public_key_from_pem
import logging
from mongython.models.base import BaseDocument
from mongython.models.message import TokenWindowState, Message
from mongython.models.user import User

logger = logging.getLogger(__name__)


class Conversation(BaseDocument):
    """Enhanced conversation model with message tracking and metadata."""

    # Relationship to user - using proper Link typing
    user: Link[User]

    # Basic conversation data
    title: Optional[str] = None

    # Timestamps
    created_at: datetime = Field(default_factory=datetime.now)
    updated_at: Annotated[datetime, Indexed()] = Field(default_factory=datetime.now)

    # Token tracking
    token_window: TokenWindowState = Field(default_factory=TokenWindowState)

    # Encryption fields
    encrypted_conversation_key: Optional[str] = None  # AES key encrypted with user's public key
    key_version: int = Field(default=1)  # For future key rotation support

    class Settings:
        name = "conversations"

    @classmethod
    async def create_initial(cls, user: User, user_public_key: Optional[str] = None) -> "Conversation":
        """Create a new conversation with optional key generation."""
        conversation = cls(
            user=user,
            created_at=datetime.now(),
            updated_at=datetime.now(),
        )

        # Generate and encrypt conversation key if public key is provided
        if user_public_key:
            try:
                # Generate a new AES key for the conversation
                conversation_key = generate_aes_key()
                
                # Load the user's public key
                public_key = load_public_key_from_pem(user_public_key)
                
                # Encrypt the conversation key with the user's public key
                encrypted_key = encrypt_with_rsa_public_key(public_key, conversation_key)
                
                # Store the encrypted key
                conversation.encrypted_conversation_key = base64.b64encode(encrypted_key).decode('utf-8')
                logger.debug(f"Generated and encrypted conversation key for conversation {conversation.id}")
            except Exception as e:
                logger.error(f"Failed to generate/encrypt conversation key for user {user.id}: {e}", exc_info=True)
                # Raise an HTTP exception instead of passing silently
                # This ensures the client gets an error response
                from fastapi import HTTPException, status # Import inside method to avoid circular dependency if needed
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=f"Failed to set up encryption for new conversation: {e}"
                )

        await conversation.save()
        return conversation

    async def add_user_message(
        self,
        content: str,
        parent_message_id: Optional[UUID4] = None,
    ) -> "Message":
        """Add a user message to the conversation."""
        # Update conversation timestamp
        self.updated_at = datetime.now()
        await self.save()

        # Create the message
        message = await Message.create_user_message(
            conversation_id=self.id,
            content=content,
            user=self.user,
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
    ) -> "Message":
        """Add an assistant message to the conversation."""
        # Create the message
        message = await Message.create_assistant_message(
            conversation_id=self.id,
            content=content,
            model_id=model_id,
            user=self.user,
            parent_message_id=parent_message_id,
            token_count=token_count,
        )

        # Update token window
        self.token_window.update_from_message(message, is_input=False)
        await self.save()

        return message

    async def get_messages(self) -> List["Message"]:
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

    async def get_message_thread(self, message_id: UUID4) -> List["Message"]:
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
                "prompt_tokens": self.token_window.prompt_tokens,
                "completion_tokens": self.token_window.completion_tokens,
            },
            # Removed tags, detected_topics, summary
        }
