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
from mongython.models.message import (
    Message,
)  # TokenWindowState removed as it's part of Conversation now
from mongython.api.errors import ErrorResponse
from mongython.api.users import get_current_user
from mongython.models.user import User
from mongython.utils.server_encryption import (
    server_encryption,
)  # Import server encryption
import openai  # Import openai
from mongython.models.llm_model import (
    LLMModel,
)  # Import LLMModel for summary model lookup
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

SUMMARY_MODEL = os.getenv("SUMMARY_MODEL", "llama-3.1-8b-instant")
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
    # tags: List[str] = [] # Removed
    # detected_topics: List[str] = [] # Removed
    # summary: Optional[str] = None # Removed


class ConversationListResponse(BaseModel):
    conversations: List[ConversationResponse]


class MessageResponse(BaseModel):
    id: str
    role: str
    # content: Optional[str] = None # Removed plain content field
    content: Optional[str] = (
        None  # Renamed from encrypted_content, holds encrypted data
    )
    # is_encrypted: bool # Removed
    # E2EE fields now returned by Message.to_dict()
    encrypted_key: Optional[str] = None
    iv: Optional[str] = None
    tag: Optional[str] = None
    created_at: str
    model_id: Optional[str] = None
    token_count: int = 0
    parent_id: Optional[str] = None
    # encryption_metadata: Optional[Dict[str, Any]] = None # Optionally include if needed


class MessageListResponse(BaseModel):
    messages: List[MessageResponse]


class MessageRequest(BaseModel):
    role: str
    # Content is now always the base64 encrypted string (IV + Ciphertext + Tag)
    content: str  # Renamed from encrypted_content conceptually
    # is_encrypted: bool = False # Removed, always true
    # E2EE fields required from client
    encrypted_key: Optional[str] = None
    iv: Optional[str] = None
    tag: Optional[str] = None
    model_id: Optional[str] = None
    parent_id: Optional[str] = None
    # encryption_metadata: Optional[Dict[str, Any]] = None # Optional metadata from client


class TitleUpdateRequest(BaseModel):
    title: str


# --- New Models for Summarization ---
class SummarizeRequestMessage(BaseModel):
    role: str
    content: Optional[str] = None  # Renamed from encrypted_content
    # encrypted_content: Optional[str] = None # Removed
    # Add the missing optional fields expected for decryption
    encrypted_key: Optional[str] = None
    iv: Optional[str] = None
    tag: Optional[str] = None
    # is_encrypted: bool # Removed


class SummarizeRequest(BaseModel):
    messages: List[SummarizeRequestMessage]


class SummarizeResponse(BaseModel):
    title: str


# --- End New Models ---


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
                    # tags=conv.tags, # Removed
                    # detected_topics=conv.detected_topics, # Removed
                    # summary=conv.summary, # Removed
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


@router.post("")
async def create_conversation(
    current_user: User = Depends(get_current_user),
) -> Dict[str, Any]:
    """Create a new conversation."""
    try:
        # Create conversation with user's public key for encryption
        conversation = await Conversation.create_initial(
            current_user,
            user_public_key=(
                current_user.ed25519_public_key
                if current_user.ed25519_public_key
                else None
            ),
        )

        logger.info(
            f"Created conversation {conversation.id} for user {current_user.id}"
        )
        logger.debug(
            f"Encryption setup: has_public_key={bool(current_user.ed25519_public_key)}, has_conv_key={bool(conversation.encrypted_conversation_key)}"
        )

        # Prepare the response
        response_data = conversation.dict()  # Convert Beanie doc to dict
        response_data["id"] = str(conversation.id)  # Ensure ID is a string
        response_data["user_id"] = str(current_user.id)  # Add user ID as string

        # Return necessary keys for E2EE setup
        response_data["server_public_key"] = server_encryption.get_public_key_pem()
        response_data["user_public_key"] = (
            current_user.ed25519_public_key if current_user.ed25519_public_key else None
        )

        return JSONResponse(content=response_data, status_code=status.HTTP_201_CREATED)
    except Exception as e:
        logger.error(f"Failed to create conversation: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create conversation: {str(e)}",
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
        # tags=conversation.tags, # Removed
        # detected_topics=conversation.detected_topics, # Removed
        # summary=conversation.summary, # Removed
    )


# --- New Summarization Endpoint ---
@router.put("/{conversation_id}/summarize", response_model=SummarizeResponse)
async def summarize_conversation(
    conversation_id: str,
    request: SummarizeRequest = Body(...),
    current_user: User = Depends(get_current_user),
):
    """Generate and update the title for a conversation based on initial messages."""
    try:
        conv_uuid = UUID4(conversation_id)
        conversation = await Conversation.find_one(
            Conversation.id == conv_uuid, fetch_links=True
        ).find_one(Conversation.user.id == current_user.id, fetch_links=True)

        if not conversation:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Conversation not found or access denied",
            )

        if not request.messages:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No messages provided for summarization",
            )

        # Decrypt received messages (encrypted with server key)
        decrypted_messages = []
        for msg_data in request.messages:
            # is_encrypted removed, assume always encrypted. Check for content instead.
            if not msg_data.content:
                logger.warning(
                    f"Received message with no content for summarization in conv {conversation_id}, skipping."
                )
                continue  # Or raise error? Skipping for now.
            try:
                # Use the renamed 'content' field
                encrypted_components = {
                    "encrypted_content": msg_data.content,  # Use renamed field, map to expected key
                    "encrypted_key": getattr(
                        msg_data, "encrypted_key", None
                    ),  # Handle potential missing optional fields
                    "iv": getattr(msg_data, "iv", None),
                    "tag": getattr(msg_data, "tag", None),
                }
                # Ensure all components needed for decryption are present
                # Check encrypted_content specifically, others might be optional depending on exact decryption needs
                if (
                    not encrypted_components["encrypted_content"]
                    or not encrypted_components["encrypted_key"]
                    or not encrypted_components["iv"]
                    or not encrypted_components["tag"]
                ):
                    logger.warning(
                        f"Skipping message due to missing encryption components for summarization: {encrypted_components}"
                    )
                    continue

                decrypted_content = server_encryption.decrypt_from_client(
                    encrypted_components
                )
                decrypted_messages.append(
                    {"role": msg_data.role, "content": decrypted_content}
                )
            except Exception as e:
                logger.error(
                    f"Failed to decrypt message for summarization in conv {conversation_id}: {e}",
                    exc_info=True,
                )
                # Decide whether to proceed with partial context or fail
                # For now, let's fail if any decryption error occurs to ensure title quality
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Failed to decrypt message content for summarization: {e}",
                )

        if not decrypted_messages:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Could not decrypt any messages for summarization",
            )

        # Prepare prompt for summarization model (Simplified)
        summary_prompt = {
            "role": "system",
            "content": (
                "You are the best conversation summarizer in the world."
                "You generate fun, engaging, and descriptive titles for conversations."
                "Generate AN EXTREMELY SHORT descriptive title "
                "(3-4 words, emojis allowed) for this conversation "
                "based on the first few messages. For example, "
                "'Hiking Trip Preparation'"
                "Do not include any other text in your response, just the title."
                "Do not format it, just return the text as a string with no markdown formatting."
                "I REPEAT, it MUST BE SHORT, like 3-5 words, no more than 10 characters!!."
            ),
        }
        # Format the conversation history as a single string for the user message
        conversation_text = "\n".join(
            [f"{msg['role']}: {msg['content']}" for msg in decrypted_messages]
        )
        llm_input_messages = [
            summary_prompt,
            {"role": "user", "content": f"Conversation history: {conversation_text}"},
        ]

        # Log the exact input being sent to the LLM
        logger.debug(f"Sending messages to summarization LLM: {llm_input_messages}")

        # Call the summarization LLM
        try:
            logger.info(
                f"Calling summarization model ({SUMMARY_MODEL}) for conv {conversation_id}"
            )
            # Use the user's auth token, consistent with the /generate endpoint
            if not current_user.auth_token:
                logger.error(
                    f"User {current_user.id} missing auth token for summarization call."
                )
                raise HTTPException(
                    status_code=500, detail="User auth token missing for summarization."
                )

            client_ = openai.AsyncOpenAI(
                api_key=current_user.auth_token, base_url=LITELLM_URL
            )
            logger.debug(f"Summarization input messages: {llm_input_messages}")
            response = await client_.chat.completions.create(
                model=SUMMARY_MODEL,
                messages=llm_input_messages,
                max_tokens=10,  # Keep title short
                temperature=0.77,  # Be somewhat creative but not too random
            )
            logger.debug(f"Summarization response: {response}")
            generated_title = (
                response.choices[0]
                .message.content.strip()
                .replace("'", "")
                .replace('"', "")
                .replace("*", "")
            )
            logger.info(
                f"Generated title for conv {conversation_id}: '{generated_title}'"
            )

            # Basic cleanup/validation
            if not generated_title:
                generated_title = conversation_text  # Fallback title

            # Limit length if needed (optional)
            generated_title = generated_title[:50]  # Max 50 chars

        except Exception as llm_e:
            logger.error(
                f"Error calling summarization model for conv {conversation_id}: {llm_e}",
                exc_info=True,
            )
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail=f"Failed to generate conversation title: {llm_e}",
            )

        # Update conversation title in DB
        conversation.title = generated_title
        conversation.updated_at = datetime.now()
        await conversation.save()
        logger.info(f"Updated title for conversation {conversation_id}")

        return SummarizeResponse(title=generated_title)

    except HTTPException:
        raise  # Re-raise validation/auth errors
    except Exception as e:
        logger.error(
            f"Unexpected error during conversation summarization for {conversation_id}: {e}",
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to summarize conversation: {e}",
        )


# --- End New Summarization Endpoint ---


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

    logger.debug(
        f"Fetching messages for conversation {conversation_id} (User: {current_user.id})"
    )
    messages = (
        await Message.find(Message.conversation_id == conversation.id)
        .sort("+created_at")
        .to_list()
    )
    logger.info(
        f"Found {len(messages)} messages in DB for conversation {conversation_id}"
    )

    response_messages = []
    for msg in messages:
        try:
            msg_dict = msg.to_dict()
            logger.debug(
                f"Processing message {msg.id} for response. Role: {msg_dict.get('role')}, HasContent: {msg_dict.get('content') is not None}, HasKey: {msg_dict.get('encrypted_key') is not None}"
            )
            response_messages.append(MessageResponse(**msg_dict))
        except Exception as e:
            logger.error(
                f"Error converting message {msg.id} to dict for response: {e}",
                exc_info=True,
            )
            # Optionally skip the message or add a placeholder

    logger.debug(
        f"Returning {len(response_messages)} messages for conversation {conversation_id}"
    )
    return MessageListResponse(messages=response_messages)


@router.post("/{conversation_id}/add_message", response_model=MessageResponse)
async def add_message(
    conversation_id: str,
    message_data: MessageRequest,
    current_user: User = Depends(get_current_user),
):
    """
    Add a message to a conversation.
    If message_data.is_encrypted is True, message_data.content is expected
    to be the Base64 encoded encrypted string (IV + Ciphertext + Tag).
    """
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

        # Add the message based on role. is_encrypted is removed, assume always encrypted.
        # message_content = message_data.content # Keep for clarity below
        # is_encrypted = message_data.is_encrypted # Removed

        if message_data.role == "user":
            # Create the message document directly, setting new E2EE fields
            message = Message(
                role="user",
                conversation_id=conv_uuid,
                parent_message_id=parent_message_id,
                # is_encrypted=is_encrypted, # Removed
                content=message_data.content,  # Assign encrypted content directly
                encrypted_key=message_data.encrypted_key,
                iv=message_data.iv,
                tag=message_data.tag,
                token_count=0,  # Cannot estimate tokens for encrypted
                # encryption_metadata=message_data.encryption_metadata # Optional
            )
            # Removed if/else based on is_encrypted
            await message.save()
            # Update conversation token window
            conversation.token_window.update_from_message(message, is_input=True)

        elif message_data.role == "assistant":
            if not message_data.model_id:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="model_id is required for assistant messages",
                )

            # Parent message ID logic remains the same (find most recent user message if needed)
            if not parent_message_id:
                # Find the most recent user message to use as parent
                try:
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
                    else:  # Handle case where no user message exists yet
                        parent_message_id = None  # Or handle as error if required
                except Exception as e:
                    logger.error(
                        f"Error finding parent user message: {e}", exc_info=True
                    )
                    parent_message_id = None  # Fallback or raise error

            # Create the message document directly, setting new E2EE fields
            message = Message(
                role="assistant",
                conversation_id=conv_uuid,
                parent_message_id=parent_message_id,
                model_id=message_data.model_id,
                content=message_data.content,  # Assign encrypted content directly
                encrypted_key=message_data.encrypted_key,
                iv=message_data.iv,
                tag=message_data.tag,
                token_count=0,  # Cannot estimate tokens for encrypted
            )
            await message.save()
            # Update conversation token window
            conversation.token_window.update_from_message(message, is_input=False)

        else:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid message role. Must be 'user' or 'assistant'",
            )

        # Update conversation timestamp
        conversation.updated_at = datetime.now()
        await conversation.save()  # Save token window and updated_at changes

        # Return the created message using its to_dict method
        return MessageResponse(**message.to_dict())

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


@router.delete("/me/all", response_model=Dict[str, Any], status_code=status.HTTP_200_OK)
async def delete_my_conversations(
    current_user: User = Depends(get_current_user),
):
    """Delete all conversations and associated messages for the authenticated user."""
    try:
        logger.info(
            f"Initiating deletion of all conversations for user {current_user.id} ({current_user.username})"
        )
        # Find all conversations for the current user
        conversations = await Conversation.find(
            Conversation.user.id == current_user.id
        ).to_list()

        deleted_conversations_count = 0
        deleted_messages_count = 0

        if not conversations:
            logger.info(f"No conversations found for user {current_user.id} to delete.")
            return {
                "message": "No conversations found to delete.",
                "deleted_conversations_count": 0,
                "deleted_messages_count": 0,
            }

        # Delete all messages for each conversation, then the conversation itself
        for conversation in conversations:
            try:
                messages_deleted = await Message.find(
                    Message.conversation_id == conversation.id
                ).delete()
                deleted_messages_count += (
                    messages_deleted.deleted_count if messages_deleted else 0
                )
                await conversation.delete()
                deleted_conversations_count += 1
                logger.debug(
                    f"Deleted conversation {conversation.id} and {messages_deleted.deleted_count if messages_deleted else 0} messages for user {current_user.id}"
                )
            except Exception as inner_e:
                logger.error(
                    f"Error deleting conversation {conversation.id} or its messages for user {current_user.id}: {inner_e}",
                    exc_info=True,
                )
                # Decide whether to continue or stop on error. Continuing for now.

        logger.info(
            f"Successfully deleted {deleted_conversations_count} conversations and {deleted_messages_count} messages for user {current_user.id}"
        )
        return {
            "message": "All conversations deleted successfully",
            "deleted_conversations_count": deleted_conversations_count,
            "deleted_messages_count": deleted_messages_count,
        }

    except Exception as e:
        logger.error(
            f"Error deleting all conversations for user {current_user.id}: {e}",
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"An unexpected error occurred while deleting conversations: {str(e)}",
        )


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
            # Use the Message model's to_dict method
            MessageResponse(**msg.to_dict())
            for msg in thread
        ]
    )


@router.delete("/all", response_model=dict)
async def delete_all_conversations(
    current_user: User = Depends(get_current_user),
):
    """Delete all conversations."""
    try:
        # Find all conversations for the current user
        conversations = await Conversation.find(
            Conversation.user.id == current_user.id
        ).to_list()

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


# --- Admin Endpoints ---


@router.delete("/admin/all", response_model=dict)
async def admin_delete_all_conversations():
    """Admin endpoint to delete all conversations from all users. No auth required - meant for local admin use."""
    try:
        # Find all conversations
        conversations = await Conversation.find_all().to_list()

        # Delete all messages for each conversation
        total_messages = 0
        for conversation in conversations:
            messages = await Message.find(
                Message.conversation_id == conversation.id
            ).to_list()
            total_messages += len(messages)
            for message in messages:
                await message.delete()
            await conversation.delete()

        return {
            "status": "success",
            "conversations_deleted": len(conversations),
            "messages_deleted": total_messages,
        }
    except Exception as e:
        logger.error(f"Admin error deleting all conversations: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error deleting all conversations: {str(e)}",
        )


@router.delete("/admin/user/{username}", response_model=dict)
async def admin_delete_user_conversations(username: str):
    """Admin endpoint to delete all conversations for a specific user. No auth required - meant for local admin use."""
    try:
        # Find the user first
        user = await User.find_one(User.username == username)
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"User {username} not found",
            )

        # Find all conversations for this user
        conversations = await Conversation.find(
            Conversation.user.id == user.id
        ).to_list()

        # Delete all messages and conversations
        total_messages = 0
        for conversation in conversations:
            messages = await Message.find(
                Message.conversation_id == conversation.id
            ).to_list()
            total_messages += len(messages)
            for message in messages:
                await message.delete()
            await conversation.delete()

        return {
            "status": "success",
            "username": username,
            "conversations_deleted": len(conversations),
            "messages_deleted": total_messages,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(
            f"Admin error deleting conversations for user {username}: {e}",
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error deleting conversations for user {username}: {str(e)}",
        )
