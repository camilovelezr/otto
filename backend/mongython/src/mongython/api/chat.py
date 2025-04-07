"""API endpoints for chat."""

import logging
import os
import json
import time
import traceback
from datetime import datetime
from typing import List, Optional, Dict, Any, Union
from uuid import UUID
import io
import base64
import uuid

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding as asymmetric_padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend

from fastapi import (
    APIRouter,
    HTTPException,
    Depends,
    status,
    BackgroundTasks,
    Request,
    Body,
)
from fastapi.responses import StreamingResponse, JSONResponse
from openai import OpenAI, AsyncOpenAI, APIError
from openai.types.chat import ChatCompletionMessageParam
from mongython.models.llm_model import LLMModel
from mongython.models.conversation import Conversation
from mongython.models.message import Message
from mongython.api.errors import ErrorResponse
from mongython.api.users import get_current_user
from mongython.models.user import User
from mongython.utils.server_encryption import server_encryption
from mongython.utils.encryption import encrypt_aes_gcm
from dotenv import load_dotenv, find_dotenv
from pydantic import BaseModel, Field, UUID4
from pydantic import validator

load_dotenv(find_dotenv())

# Load environment variables
router = APIRouter(
    prefix="/chat",
    tags=["chat"],
    responses={
        404: {"model": ErrorResponse, "description": "Not found"},
        500: {"model": ErrorResponse, "description": "Internal server error"},
    },
)

logger = logging.getLogger(__name__)

LITELLM_URL = os.getenv("LITELLM_URL")


async def save_streamed_message(
    conversation_id: str,
    user_message_id: UUID4,
    model_name: str,
    full_content: str, # Changed from response_bytes
    user_public_key: str # Need user's public key to re-encrypt
):
    """Background task to save the complete streamed message content."""
    logger.info(f"[save_streamed_message] Task started for conversation {conversation_id}, user_message {user_message_id}")

    try:
        if not full_content:
             logger.error("[save_streamed_message] Cannot save empty message content.")
             raise ValueError("Empty content provided for saving")

        # Get the conversation
        logger.debug(f"[save_streamed_message] Fetching conversation {conversation_id}")
        conversation = await Conversation.get(UUID(conversation_id)) # Use UUID directly
        if not conversation:
            logger.error(f"[save_streamed_message] Could not find conversation {conversation_id} to save streamed message")
            return
        logger.debug(f"[save_streamed_message] Found conversation {conversation_id}")

        logger.info(f"[save_streamed_message] Saving assistant message to conversation {conversation_id}")

        # Re-encrypt the full content for storage
        if not user_public_key:
             logger.error(f"[save_streamed_message] Missing user public key for saving message to conversation {conversation_id}")
             raise ValueError("Missing user public key for saving")

        try:
            logger.debug(f"[save_streamed_message] Re-encrypting assistant message content ({len(full_content)} chars) for DB storage using user's public key.")
            encrypted_final_data = server_encryption.encrypt_for_client(
                full_content,
                user_public_key
            )
            logger.debug(f"[save_streamed_message] Assistant message content re-encrypted successfully for storage.")
        except Exception as enc_error:
            logger.error(f"[save_streamed_message] Failed to re-encrypt full message for saving: {enc_error}", exc_info=True)
            raise ValueError("Failed to encrypt message for saving")

        logger.debug(f"[save_streamed_message] Creating Message object for assistant message")
        # Create the message document
        assistant_message = Message(
            role="assistant",
            conversation_id=conversation.id, # Use conversation.id directly
            parent_message_id=user_message_id,
            model_id=model_name,
            token_count=0,  # TODO: Calculate token count if needed
            user=conversation.user,
            # is_encrypted=True, # Field removed from model
            content=encrypted_final_data["encrypted_content"], # Use 'content' field for encrypted data
            encrypted_key=encrypted_final_data["encrypted_key"],
            iv=encrypted_final_data["iv"],
            tag=encrypted_final_data["tag"],
            # content=None # Field removed from model
        )

        await assistant_message.save()
        logger.info(f"[save_streamed_message] Saved assistant message {assistant_message.id} to conversation {conversation_id}")

        # Update conversation token window and timestamp
        # TODO: Implement token calculation based on full_content if needed
        # conversation.token_window.update_from_message(assistant_message, is_input=False)
        logger.debug(f"[save_streamed_message] Updating conversation {conversation_id} timestamp")
        conversation.updated_at = datetime.now()
        await conversation.save()
        logger.debug(f"[save_streamed_message] Conversation {conversation_id} timestamp updated")

    except ValueError as ve:
         logger.error(f"[save_streamed_message] Value error saving streamed message: {ve}", exc_info=True)
    except Exception as e:
        logger.error(f"[save_streamed_message] Unexpected error saving streamed message to conversation {conversation_id}: {e}", exc_info=True)


# Custom stream wrapper to capture the full response while streaming
async def stream_wrapper(stream, conversation=None, user_public_key=None, background_tasks=None, user_message_id=None, model_name=None):
    """Wrap the stream response, encrypt chunks, and save the full message."""
    # buffer = [] # No longer needed to buffer encrypted chunks for saving
    accumulated_content = "" # Still needed to accumulate for saving
    try:
        stream_response = await stream  # Await the coroutine to get the actual stream
        has_content = False  # Track if we've received any content

        async for chunk in stream_response:
            # Log the raw chunk for debugging
            # logger.debug(f"Raw LLM chunk: {chunk}") # Reduce log noise

            if not chunk.choices:
                # logger.warning(f"LLM returned chunk without choices: {chunk}") # Reduce log noise
                continue

            # Check for errors in the chunk
            if hasattr(chunk, 'error') and chunk.error:
                error_msg = getattr(chunk, 'error', 'Unknown LLM error')
                logger.error(f"LLM returned error in chunk: {error_msg}")
                # Yield an error message to the client? Or just raise?
                # yield f"data: {json.dumps({'error': str(error_msg)})}\n\n"
                raise ValueError(f"LLM error: {error_msg}")

            # Check for finish_reason
            finish_reason = chunk.choices[0].finish_reason
            if finish_reason:
                logger.info(f"LLM finish reason: {finish_reason}")
                if finish_reason not in ['stop', None, 'length', 'tool_calls']: # Allow common reasons
                    logger.warning(f"Unexpected LLM finish reason: {finish_reason}")

            # Safely access content
            content = None
            if chunk.choices[0].delta:
                 content = chunk.choices[0].delta.content

            if not content:
                # logger.debug("Skipping chunk with no content or only finish_reason") # Reduce noise
                continue

            has_content = True
            accumulated_content += content

            # Always encrypt chunks
            if not user_public_key:
                logger.error("No user public key available for encryption during stream")
                raise ValueError("Cannot stream without encryption key")

            try:
                encrypted_data = server_encryption.encrypt_for_client(content, user_public_key)
                response_data = {
                    "content": encrypted_data["encrypted_content"], # Use 'content' key for consistency
                    "encrypted_key": encrypted_data["encrypted_key"],
                    "iv": encrypted_data["iv"],
                    "tag": encrypted_data["tag"],
                    "is_encrypted": True,
                    "role": "assistant"
                }
                # Log the dictionary before sending
                logger.debug(f"[stream_wrapper] Preparing to yield chunk. Keys: {list(response_data.keys())}")
                # Log lengths/types to avoid logging sensitive keys directly
                log_vals = {k: type(v).__name__ + (f" (len={len(v)})" if isinstance(v, str) else "") for k, v in response_data.items()}
                logger.debug(f"[stream_wrapper] Chunk data details: {log_vals}")

                # Yield individual encrypted chunk
                sse_data = json.dumps(response_data)
                yield f"data: {sse_data}\n\n"
            except Exception as e:
                logger.error(f"[stream_wrapper] Failed to encrypt and yield chunk: {e}", exc_info=True)
                # Decide if we should stop the stream or continue
                raise ValueError(f"Encryption/Yield failed: {e}")

        # After the loop, check if we received any content at all
        if not has_content:
            logger.error("LLM stream finished without yielding any content.")
            # Optionally yield an error marker to the client
            # yield f"data: {json.dumps({'error': 'Empty response from LLM'})}\n\n"
            # No need to raise here, just finish stream and don't save.
            return # Exit the generator

        # ** REMOVED: Do not send final accumulated message chunk **

        # Schedule background task to save the full accumulated message
        if conversation and background_tasks and user_message_id and model_name and accumulated_content:
             if not user_public_key:
                 logger.error("Cannot save message - user public key missing for background task.")
             else:
                 logger.debug(f"Scheduling background task to save accumulated content ({len(accumulated_content)} chars)")
                 background_tasks.add_task(
                     save_streamed_message,
                     conversation_id=str(conversation.id),
                     user_message_id=user_message_id,
                     model_name=model_name,
                     full_content=accumulated_content, # Pass the full decrypted content
                     user_public_key=user_public_key # Pass key for re-encryption
                 )
    except Exception as e:
        logger.error(f"Error in stream wrapper: {e}", exc_info=True)
        # Log additional context about the error
        if isinstance(e, APIError):
            logger.error(f"LLM API Error: {e.response}")
        raise
    finally:
        buffer = None  # Clear the buffer


# Create a request model for the chat endpoint
class ChatRequest(BaseModel):
    messages: List[Dict[str, Any]]
    stream: bool = Field(default=False)
    params: Optional[Dict[str, Any]] = None
    conversation_id: Optional[str] = None

    @validator('messages')
    def validate_messages(cls, v):
        for msg in v:
            if 'role' not in msg:
                raise ValueError("Each message must have a 'role' field")
            if 'content' not in msg:
                raise ValueError("Each message must have a 'content' field")
            # Handle is_encrypted as either string or boolean
            if 'is_encrypted' in msg:
                if isinstance(msg['is_encrypted'], str):
                    msg['is_encrypted'] = msg['is_encrypted'].lower() == 'true'
                elif isinstance(msg['is_encrypted'], bool):
                    pass  # Keep as is
                else:
                    raise ValueError("is_encrypted must be a string or boolean")
        return v


@router.post("/{model_name}/generate")
async def chat(
    model_name: str,
    background_tasks: BackgroundTasks,
    request: ChatRequest = Body(...),
    current_user: User = Depends(get_current_user),
):
    """Generate a response from a model using OpenAI API."""

    # Extract parameters from the request body
    messages_data = request.messages
    stream = request.stream
    params = request.params
    conversation_id = request.conversation_id

    logger.info(f"Processing chat request: stream={stream}, conversation_id={conversation_id}")

    # Get the model from the database using model_id from the path parameter
    model = await LLMModel.find_one(LLMModel.model_id == model_name) # Corrected: Use model_id for lookup
    logger.info(f"Model found by ID ({model_name}): {model}")
    if not model:
        logger.error(f"Model with ID {model_name} not found")
        available_models = await LLMModel.find_all().to_list() # Corrected: Added .to_list()
        logger.info(f"Available models: {available_models}")
        raise HTTPException(status_code=404, detail="Model not found")

    # Check if user has an auth token
    if not current_user.auth_token:
        logger.error(f"User {current_user.id} does not have an auth token")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User does not have an auth token"
        )

    # Initialize OpenAI client with user's auth token
    client = AsyncOpenAI(
        base_url=LITELLM_URL,
        api_key=current_user.auth_token,  # Use user's auth token
        timeout=60.0,
        max_retries=2,
    )

    # Check if this is a Groq model (for special handling)
    is_groq_model = False
    if model.provider and model.provider.lower() == "groq":
        is_groq_model = True
        logger.info(f"Detected Groq model: {model_name}")

    # Validate conversation_id if provided
    conversation = None
    if conversation_id:
        try:
            conversation = await Conversation.find_one(
                Conversation.id == UUID4(conversation_id),
                fetch_links=True,
            ).find_one(Conversation.user.id == current_user.id, fetch_links=True)

            if not conversation:
                 logger.error(f"Conversation {conversation_id} not found or user mismatch for user {current_user.id}")
                 raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail="Conversation not found or access denied",
                )
        except ValueError:
             raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid conversation ID format",
            )
        except Exception as e:
            logger.error(f"Error retrieving conversation {conversation_id}: {e}", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail=f"Error accessing conversation data: {str(e)}",
            )

    # Process messages for LLM and identify the last user message for saving
    llm_messages = []
    user_message = None # This will hold the Message object if the last message is saved
    last_message_data = None # Store the raw last message from the request
    last_decrypted_content = None # Store the decrypted content of the last message

    if messages_data:
        last_message_data = messages_data[-1]

    # Process all messages for decryption and adding to LLM context
    for i, msg in enumerate(messages_data):
        is_last_message = (i == len(messages_data) - 1)
        try:
            is_encrypted = msg.get('is_encrypted', False)

            if is_encrypted:
                encrypted_content = msg.get('encrypted_content')
                if not encrypted_content:
                    logger.error(f"Encrypted message {msg.get('id', 'N/A')} missing encrypted_content")
                    raise HTTPException(status_code=400, detail="Encrypted message missing required fields")

                try:
                    logger.debug(f"Attempting to decrypt message {msg.get('id', 'N/A')} for LLM")
                    encrypted_data = {
                        'encrypted_content': encrypted_content,
                        'encrypted_key': msg.get('encrypted_key'),
                        'iv': msg.get('iv'),
                        'tag': msg.get('tag')
                    }
                    encrypted_data = {k: v for k, v in encrypted_data.items() if v is not None}
                    logger.debug(f"Data for server decryption (msg {msg.get('id', 'N/A')}): {list(encrypted_data.keys())}")
                    decrypted_content = server_encryption.decrypt_from_client(encrypted_data)
                    logger.debug(f"Successfully decrypted message {msg.get('id', 'N/A')} for LLM. Content preview: {decrypted_content[:50]}...")
                except Exception as e:
                    logger.error(f"Failed to decrypt message {msg.get('id', 'N/A')}: {e}", exc_info=True)
                    raise HTTPException(status_code=400, detail=f"Failed to decrypt message {msg.get('id', 'N/A')}")
            else:
                logger.error(f"Received unencrypted message {msg.get('id', 'N/A')} from client.")
                raise HTTPException(status_code=400, detail="All messages must be encrypted")

            if not decrypted_content:
                logger.warning(f"Empty message {msg.get('id', 'N/A')} after decryption, skipping")
                continue

            # Add processed message to LLM context
            logger.debug(f"Adding message {msg.get('id', 'N/A')} to LLM context (Role: {msg['role']})")
            llm_messages.append({"role": msg["role"], "content": decrypted_content})

            # If this is the last message, store its decrypted content
            if is_last_message:
                last_decrypted_content = decrypted_content

        except Exception as e:
            logger.error(f"Error processing message {msg.get('id', 'N/A')} in loop: {e}", exc_info=True)
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"Error processing message {msg.get('id', 'N/A')}: {str(e)}")

    # --- Save ONLY the LAST user message AFTER the loop ---
    if conversation and last_message_data and last_message_data.get("role") == "user":
        logger.debug(f"Processing LAST message (Role: user) for saving.")
        if not last_decrypted_content:
             logger.error("Cannot save last user message: Decrypted content is missing.")
             # Handle this error appropriately, maybe raise HTTPException
        elif not current_user.public_key:
            logger.error(f"Cannot save last user message for user {current_user.id} - User public key missing.")
            raise HTTPException(status_code=500, detail="User public key not found for saving message.")
        else:
            try:
                logger.debug(f"Re-encrypting last user message content for DB storage using user's public key.")
                encrypted_for_storage = server_encryption.encrypt_for_client(
                    last_decrypted_content, # Use the stored decrypted content of the last message
                    current_user.public_key
                )
                logger.debug(f"Last user message content re-encrypted successfully for storage.")

                logger.debug(f"Creating Message object for last user message")
                # Create the Message object for the last user message
                user_message = Message(
                    role="user",
                    conversation_id=conversation.id,
                    model_id=model_name, # Still passing model_name, consider if needed
                    user=current_user,
                    content=encrypted_for_storage["encrypted_content"],
                    encrypted_key=encrypted_for_storage["encrypted_key"],
                    iv=encrypted_for_storage["iv"],
                    tag=encrypted_for_storage["tag"],
                )
                await user_message.save()
                logger.info(f"Saved LAST user message {user_message.id} (re-encrypted) to conversation {conversation.id}")

            except Exception as save_exc:
                logger.error(f"Failed to re-encrypt or save last user message: {save_exc}", exc_info=True)
                raise HTTPException(status_code=500, detail="Failed to prepare or save user message.")

    # --- End of saving logic ---

    # Create request parameters for LLM (using the llm_messages built in the loop)
    # Use the provider_model_id from the fetched model document for the LiteLLM call
    request_params = {
        "model": model.provider_model_id, # Corrected: Use the provider-specific ID for LiteLLM
        "messages": llm_messages, # Use the potentially modified llm_messages list
        "stream": stream,
    }

    if params:
        request_params.update(params)

    logger.info(f"Request parameters: {request_params}")

    try:
        if stream:
            # Return streaming response
            return StreamingResponse(
                stream_wrapper(
                    client.chat.completions.create(**request_params),
                    conversation=conversation,
                    user_public_key=current_user.public_key,
                    background_tasks=background_tasks,
                    user_message_id=user_message.id if user_message else None,
                    model_name=model_name
                ),
                media_type="text/event-stream",
            )
        else:
            # Handle non-streaming response
            try:
                response = await client.chat.completions.create(**request_params)
                logger.debug(f"Raw LLM response: {response}")

                if not response.choices:
                    logger.error("LLM returned empty choices")
                    raise ValueError("No response choices from LLM")

                if response.choices[0].finish_reason not in ['stop', None]:
                    logger.warning(f"Unexpected finish reason: {response.choices[0].finish_reason}")

                content = response.choices[0].message.content
                if not content:
                    logger.error("LLM returned empty content")
                    raise ValueError("Empty response from LLM")
                
                # Encrypt response for client
                if current_user.public_key:
                    try:
                        encrypted_data = server_encryption.encrypt_for_client(
                            content,
                            current_user.public_key
                        )
                        return JSONResponse(content={
                            "encrypted_content": encrypted_data["encrypted_content"],
                            "encrypted_key": encrypted_data["encrypted_key"],
                            "iv": encrypted_data["iv"],
                            "tag": encrypted_data["tag"],
                            "is_encrypted": True
                        })
                    except Exception as e:
                        logger.error(f"Failed to encrypt response: {e}", exc_info=True)
                        raise HTTPException(
                            status_code=500,
                            detail="Failed to encrypt response"
                        )
                
                return JSONResponse(content={"content": content, "is_encrypted": False})
            except APIError as api_e:
                logger.error(f"LLM API Error: {api_e.response}", exc_info=True)
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"LLM service error: {str(api_e)}"
                )
            except ValueError as ve:
                logger.error(f"LLM response validation error: {ve}", exc_info=True)
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=str(ve)
                )
            except Exception as e:
                logger.error(f"Unexpected error in LLM response handling: {e}", exc_info=True)
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=str(e)
                )

    except Exception as e:
        logger.error(f"Error generating response: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=str(e)
        )
