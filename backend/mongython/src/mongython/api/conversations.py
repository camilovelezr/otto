"""API endpoints for managing conversations."""

import logging
import os
from typing import List, Optional, Dict, Any
from datetime import datetime

from fastapi import APIRouter, HTTPException, Depends, Body, Query, status
from fastapi.responses import JSONResponse
import httpx
import openai
from pydantic import BaseModel, UUID4

from mongython.models.conversation import Conversation
from mongython.models.message import Message, TokenWindowState
from mongython.api.errors import ErrorResponse
from mongython.api.users import get_current_user
from mongython.models.user import User
from dotenv import load_dotenv, find_dotenv
import os

load_dotenv(find_dotenv())

router = APIRouter(
    prefix="/conversations",
    tags=["conversations"],
    responses={
        404: {"model": ErrorResponse, "description": "Not found"},
        500: {"model": ErrorResponse, "description": "Internal server error"},
    },
)

logger = logging.getLogger(__name__)

SUMMARY_MODEL = os.getenv("SUMMARY_MODEL", "llama-3.2-1b-preview")
LITELLM_MASTER_KEY = os.getenv("LITELLM_MASTER_KEY")
LITELLM_URL = os.getenv("LITELLM_URL")

logger.info(f"SUMMARY_MODEL: {SUMMARY_MODEL}")
logger.info(f"LITELLM_MASTER_KEY: {LITELLM_MASTER_KEY}")
logger.info(f"LITELLM_URL: {LITELLM_URL}")


# Request and response models
class ConversationResponse(BaseModel):
    id: str
    title: Optional[str] = None
    created_at: str
    updated_at: str
    token_window: Dict[str, Any]
    tags: List[str] = []
    detected_topics: List[str] = []
    summary: Optional[str] = None


class ConversationListResponse(BaseModel):
    conversations: List[ConversationResponse]


class MessageResponse(BaseModel):
    id: str
    role: str
    content: str
    created_at: str
    model_id: Optional[str] = None
    token_count: int = 0
    parent_id: Optional[str] = None


class MessageListResponse(BaseModel):
    messages: List[MessageResponse]


class MessageRequest(BaseModel):
    role: str
    content: str
    model_id: Optional[str] = None
    parent_id: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None


class TitleUpdateRequest(BaseModel):
    title: str


@router.get("/list", response_model=ConversationListResponse)
async def get_conversations(
    current_user: User = Depends(get_current_user),
    limit: int = Query(20, gt=0, le=100),
    skip: int = Query(0, ge=0),
):
    """Get a list of conversations for the current user."""
    try:
        # Get conversations in reverse chronological order (newest first)
        conversations = (
            await Conversation.find(
                Conversation.user.id == current_user.id, fetch_links=True
            )
            .sort("-updated_at")
            .limit(limit)
            .skip(skip)
            .to_list()
        )

        return ConversationListResponse(
            conversations=[
                ConversationResponse(
                    id=str(conv.id),
                    title=conv.title,
                    created_at=conv.created_at.isoformat(),
                    updated_at=conv.updated_at.isoformat(),
                    token_window=conv.token_window.dict(),
                    tags=conv.tags,
                    detected_topics=conv.detected_topics,
                    summary=conv.summary,
                )
                for conv in conversations
            ]
        )
    except Exception as e:
        logger.error(f"Error getting conversations: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Server error: {str(e)}",
        )


@router.post(
    "/create", response_model=ConversationResponse, status_code=status.HTTP_201_CREATED
)
async def create_conversation(current_user: User = Depends(get_current_user)):
    """Create a new conversation."""
    conversation = await Conversation.create_initial(current_user.id)

    return ConversationResponse(
        id=str(conversation.id),
        title=conversation.title,
        created_at=conversation.created_at.isoformat(),
        updated_at=conversation.updated_at.isoformat(),
        token_window=conversation.token_window.dict(),
        tags=conversation.tags,
        detected_topics=conversation.detected_topics,
        summary=conversation.summary,
    )


@router.get("/{conversation_id}/get", response_model=ConversationResponse)
async def get_conversation(
    conversation_id: str,
    current_user: User = Depends(get_current_user),
):
    """Get details for a specific conversation."""
    conversation = await Conversation.find_one(
        Conversation.id == UUID4(conversation_id), fetch_links=True
    ).find_one(Conversation.user.id == current_user.id, fetch_links=True)

    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    return ConversationResponse(
        id=str(conversation.id),
        title=conversation.title,
        created_at=conversation.created_at.isoformat(),
        updated_at=conversation.updated_at.isoformat(),
        token_window=conversation.token_window.dict(),
        tags=conversation.tags,
        detected_topics=conversation.detected_topics,
        summary=conversation.summary,
    )


@router.put("/{conversation_id}/update_title", response_model=ConversationResponse)
async def update_conversation_title(
    conversation_id: str,
    title_data: TitleUpdateRequest,
    current_user: User = Depends(get_current_user),
):
    """Update the title of a conversation."""
    conversation = await Conversation.find_one(
        Conversation.id == UUID4(conversation_id), fetch_links=True
    ).find_one(Conversation.user.id == current_user.id, fetch_links=True)

    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    conversation.title = title_data.title
    conversation.updated_at = datetime.now()
    await conversation.save()

    return ConversationResponse(
        id=str(conversation.id),
        title=conversation.title,
        created_at=conversation.created_at.isoformat(),
        updated_at=conversation.updated_at.isoformat(),
        token_window=conversation.token_window.model_dump(),
        tags=conversation.tags,
        detected_topics=conversation.detected_topics,
        summary=conversation.summary,
    )


@router.get("/{conversation_id}/get_messages", response_model=MessageListResponse)
async def get_conversation_messages(
    conversation_id: str,
    current_user: User = Depends(get_current_user),
):
    """Get all messages for a conversation."""
    conversation = await Conversation.find_one(
        Conversation.id == UUID4(conversation_id), fetch_links=True
    ).find_one(Conversation.user.id == current_user.id, fetch_links=True)

    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    messages = (
        await Message.find(Message.conversation_id == conversation.id)
        .sort("+created_at")
        .to_list()
    )

    return MessageListResponse(
        messages=[
            MessageResponse(
                id=str(msg.id),
                role=msg.role,
                content=msg.content,
                created_at=msg.created_at.isoformat(),
                model_id=msg.model_id,
                token_count=msg.token_count,
                parent_id=str(msg.parent_message_id) if msg.parent_message_id else None,
            )
            for msg in messages
        ]
    )


@router.post("/{conversation_id}/add_message", response_model=MessageResponse)
async def add_message(
    conversation_id: str,
    message_data: MessageRequest,
    current_user: User = Depends(get_current_user),
):
    """Add a message to a conversation."""
    try:
        conv_uuid = UUID4(conversation_id)
        # First find the conversation without the user check to help with debugging
        conversation = await Conversation.get(str(conv_uuid), fetch_links=True)

        if not conversation:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Conversation not found",
            )

        # Then check if this conversation belongs to the current user
        if str(conversation.user.id) != str(current_user.id):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You don't have access to this conversation",
            )
    except ValueError:
        # Handle invalid UUID
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid conversation ID format",
        )
    except Exception as e:
        # Log the exception for debugging
        print(f"Error checking conversation: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Server error: {str(e)}",
        )

    try:
        # Validate parent message if provided
        parent_message_id = None
        if message_data.parent_id:
            try:
                parent_uuid = UUID4(message_data.parent_id)
                parent_message = await Message.find_one(
                    Message.id == parent_uuid, fetch_links=True
                ).find_one(Message.conversation_id == conv_uuid, fetch_links=True)

                if not parent_message:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="Parent message not found",
                    )

                parent_message_id = parent_message.id

            except ValueError:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Invalid parent message ID format",
                )

        # Add the message based on role
        if message_data.role == "user":
            message = await conversation.add_user_message(content=message_data.content)
        elif message_data.role == "assistant":
            if not message_data.model_id:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="model_id is required for assistant messages",
                )

            if not parent_message_id:
                # Find the most recent user message to use as parent
                try:
                    # Fix the query operator issue by using a dictionary-based query
                    user_messages = (
                        await Message.find(
                            {"conversation_id": conversation.id, "role": "user"}
                        )
                        .sort("-created_at")
                        .limit(1)
                        .to_list()
                    )

                    if user_messages:
                        parent_message_id = user_messages[0].id
                except Exception as e:
                    print(f"Error finding user messages: {str(e)}")
                    # Continue without parent message if there's an error

            message = await conversation.add_assistant_message(
                content=message_data.content,
                model_id=message_data.model_id,
                parent_message_id=parent_message_id,
                metadata=message_data.metadata,
            )
        else:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid message role. Must be 'user' or 'assistant'",
            )

        # Generate title after we have multiple messages
        try:
            message_count = await Message.find(
                {"conversation_id": conversation.id}
            ).count()

            if message_count >= 2 and not conversation.title:
                await generate_conversation_title(conversation)
        except Exception as e:
            # Don't fail the whole request if title generation fails
            print(f"Error generating title: {str(e)}")

        return MessageResponse(
            id=str(message.id),
            role=message.role,
            content=message.content,
            created_at=message.created_at.isoformat(),
            model_id=message.model_id,
            token_count=message.token_count,
            parent_id=(
                str(message.parent_message_id) if message.parent_message_id else None
            ),
        )
    except HTTPException:
        # Re-raise HTTP exceptions
        raise
    except Exception as e:
        # Log the exception for debugging
        print(f"Error adding message: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Server error adding message: {str(e)}",
        )


@router.delete("/{conversation_id}/delete", status_code=status.HTTP_204_NO_CONTENT)
async def delete_conversation(
    conversation_id: str,
    current_user: User = Depends(get_current_user),
):
    """Delete a conversation and all its messages."""
    conversation = await Conversation.find_one(
        Conversation.id == UUID4(conversation_id), fetch_links=True
    ).find_one(Conversation.user.id == current_user.id, fetch_links=True)

    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    # Delete all messages
    await Message.find(Message.conversation_id == conversation.id).delete()

    # Delete the conversation
    await conversation.delete()

    # For a 204 response, don't return a JSON body - just return None
    # FastAPI will automatically convert this to a 204 No Content response
    return None


@router.get(
    "/{conversation_id}/messages/{message_id}/get_thread",
    response_model=MessageListResponse,
)
async def get_message_thread(
    conversation_id: str,
    message_id: str,
    current_user: User = Depends(get_current_user),
):
    """Get a thread of messages starting from a specific message."""
    conversation = await Conversation.find_one(
        Conversation.id == UUID4(conversation_id), fetch_links=True
    ).find_one(Conversation.user.id == current_user.id, fetch_links=True)

    if not conversation:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    thread = await conversation.get_message_thread(UUID4(message_id))

    if not thread:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Message not found",
        )

    return MessageListResponse(
        messages=[
            MessageResponse(
                id=str(msg.id),
                role=msg.role,
                content=msg.content,
                created_at=msg.created_at.isoformat(),
                model_id=msg.model_id,
                token_count=msg.token_count,
                parent_id=str(msg.parent_message_id) if msg.parent_message_id else None,
            )
            for msg in thread
        ]
    )


async def generate_conversation_title(conversation: Conversation) -> Optional[str]:
    """Generate a title for a conversation based on its messages."""
    try:

        # Get the first few messages
        messages = await conversation.get_messages()
        if len(messages) < 2:
            return None

        # Extract just what we need
        message_dicts = [
            {"role": msg.role, "content": msg.content}
            for msg in messages[:2]  # Limit to first 5 messages to avoid token limits
        ]

        # Add system prompt
        message_dicts.insert(
            0,
            {
                "role": "system",
                "content": (
                    "Generate a short, concise title (4-8 words) for this conversation. "
                    "Focus on the main topic or question. "
                    "DO NOT use phrases like 'Conversation about' or 'Discussion on'. "
                    "Just provide the title directly."
                ),
            },
        )

        # Call the LLM
        client_ = openai.AsyncOpenAI(api_key=LITELLM_MASTER_KEY, base_url=LITELLM_URL)
        response = await client_.chat.completions.create(
            model=SUMMARY_MODEL,
            messages=message_dicts,
            max_tokens=60,
            temperature=0.7,
        )
        title = response.choices[0].message.content.strip().strip('"')

        # Update conversation title
        conversation.title = title
        await conversation.save()

        return title

    except Exception as e:
        logger.error(f"Error generating conversation title: {e}")
        return None


@router.delete("/all", response_model=dict)
async def delete_all_conversations():
    """Delete all conversations."""
    try:
        # Find all conversations for the current user
        conversations = await Conversation.find().to_list()

        # Delete all messages for each conversation
        for conversation in conversations:
            # Get and delete all messages for this conversation
            messages = await conversation.get_messages()
            for message in messages:
                await message.delete()

            # Delete the conversation itself
            await conversation.delete()

        return {
            "message": "All conversations deleted successfully",
            "count": len(conversations),
        }

    except Exception as e:
        logger.error(f"Error deleting all conversations: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error deleting all conversations: {str(e)}",
        )


# @router.post("/{conversation_id}/migrate", response_model=ConversationResponse)
# async def migrate_conversation(
#     conversation_id: str,
#     current_user: User = Depends(get_current_user),
# ):
#     """Migrate a conversation from the old format to the new format."""
#     try:
#         # Import the old conversation model
#         from mongython.models.conversation_old import Conversation as OldConversation

#         # Check if the user owns the conversation
#         old_conversation = await OldConversation.get(conversation_id, fetch_links=True)
#         if not old_conversation or str(old_conversation.user.id) != current_user.id:
#             raise HTTPException(
#                 status_code=status.HTTP_404_NOT_FOUND,
#                 detail="Conversation not found",
#             )

#         # Perform the migration
#         new_conversation = await Conversation.migrate_from_old_format(conversation_id)

#         # Return the migrated conversation
#         return ConversationResponse(
#             id=str(new_conversation.id),
#             title=new_conversation.title,
#             created_at=new_conversation.created_at.isoformat(),
#             updated_at=new_conversation.updated_at.isoformat(),
#             token_window=new_conversation.token_window.dict(),
#             tags=new_conversation.tags,
#             detected_topics=new_conversation.detected_topics,
#             summary=new_conversation.summary,
#         )

#     except Exception as e:
#         logger.error(f"Error migrating conversation: {e}")
#         raise HTTPException(
#             status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
#             detail=f"Error migrating conversation: {str(e)}",
#         )
