"""Backup of the old MongoDB Conversation Model for migration purposes."""

from typing import Annotated, Literal, Optional, List, Any, Dict
from datetime import datetime
from mongython.models.user import User
from pydantic import BaseModel, UUID4
from beanie import Document, Indexed, Link
from openai.types.chat import ChatCompletion


class UserMessage(BaseModel):
    role: Literal["user"]
    content: str


def get_message_dict(
    message: UserMessage | ChatCompletion | list[ChatCompletion],
) -> dict:
    if isinstance(message, UserMessage):
        return {"role": "user", "content": message.content}
    elif isinstance(message, ChatCompletion):
        return {"role": "assistant", "content": message.choices[0].message.content}
    elif isinstance(message, list):
        return {"role": "assistant", "content": message[0].choices[0].message.content}


class Conversation(Document):
    """Legacy conversation model - kept for migration purposes only."""

    user: Link[User]
    title: Optional[str] = None
    messages: list[UserMessage | ChatCompletion | list[ChatCompletion]]
    created_at: datetime
    updated_at: Annotated[datetime, Indexed()]

    class Settings:
        name = "conversations_old"

    @classmethod
    async def get(cls, conversation_id: str) -> Optional["Conversation"]:
        """Get a conversation by ID."""
        try:
            # Use Beanie's built-in get method for ID lookups
            return await super().get(conversation_id)
        except Exception:
            return None

    async def get_messages_list(self) -> list[dict]:
        """Get the messages list as a list of dictionaries."""
        return [get_message_dict(message) for message in self.messages]
