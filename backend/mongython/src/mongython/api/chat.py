"""API endpoints for chat."""

import logging
import os
import json
import time
from typing import List, Optional, Dict, Any, Union
from uuid import UUID
import io
import base64
import uuid

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
from openai import OpenAI, AsyncOpenAI
from openai.types.chat import ChatCompletionMessageParam
from mongython.models.llm_model import LLMModel
from mongython.models.conversation import Conversation
from mongython.models.message import Message
from mongython.api.errors import ErrorResponse
from mongython.api.users import get_current_user
from mongython.models.user import User
from dotenv import load_dotenv, find_dotenv
from pydantic import BaseModel, Field, UUID4

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
    conversation_id: str, user_message_id: UUID4, model_name: str, response_bytes: bytes
):
    """Background task to save streamed message to conversation after streaming completes."""
    logger.info(f"Processing streamed message for conversation {conversation_id}")

    try:
        # Parse the SSE response to extract the final message content
        content = ""
        token_count = 0

        # Parse the SSE response
        text = response_bytes.decode("utf-8")
        events = [line for line in text.split("\n\n") if line.strip()]
        logger.debug(f"Found {len(events)} events in the streamed response")

        for event_index, event in enumerate(events):
            if not event.startswith("data:"):
                continue

            # Extract the data part of the SSE event by removing the "data:" prefix and whitespace
            event_data = event[5:].strip()

            try:
                data = json.loads(event_data)

                # Debug log the structure of the event data
                if event_index % 100 == 0 or event_index == len(events) - 1:
                    logger.debug(
                        f"Event {event_index} data structure: {json.dumps(data)[:200]}..."
                    )

                # Safer way to check for choices
                if "choices" not in data:
                    logger.debug(f"Event {event_index} has no 'choices' field")
                    continue

                if not data["choices"]:
                    logger.debug(f"Event {event_index} has empty 'choices' array")
                    continue

                # Add null check before accessing choices[0]
                choice = data["choices"][0]
                if choice is None:
                    logger.debug(f"Event {event_index} has None as first choice")
                    continue

                # Check for delta field
                if "delta" not in choice:
                    logger.debug(
                        f"Event {event_index} has no 'delta' field in first choice"
                    )
                    continue

                delta = choice.get("delta")
                if delta is None:
                    logger.debug(f"Event {event_index} has None for 'delta'")
                    continue

                # Check if content exists AND is not None
                if "content" in delta and delta["content"] is not None:
                    content += delta["content"]

                    # Log content length periodically
                    if event_index % 20 == 0:
                        logger.debug(
                            f"Content length after {event_index} events: {len(content)}"
                        )

                # If the last chunk contains usage info, use it
                if "usage" in data:
                    token_count = data["usage"].get("completion_tokens", 0)
                    logger.debug(f"Token count from usage: {token_count}")
            except json.JSONDecodeError as e:
                logger.error(f"JSON decode error on event {event_index}: {e}")
                continue
            except Exception as e:
                logger.error(f"Error processing event {event_index}: {e}")
                # Log the event data for debugging
                logger.error(f"Event data: {event_data[:200]}...")
                continue

        logger.info(f"Extracted content length: {len(content)} characters")

        # Get the conversation
        conversation = await Conversation.get(conversation_id)
        if not conversation:
            logger.error(
                f"Could not find conversation {conversation_id} to save streamed message"
            )
            return

        # Add the assistant message to the conversation
        await conversation.add_assistant_message(
            content=content,
            model_id=model_name,
            parent_message_id=user_message_id,
            token_count=token_count,
        )

        logger.info(
            f"Successfully saved streamed message to conversation {conversation_id}"
        )
    except Exception as e:
        logger.error(f"Error saving streamed message to conversation: {e}")
        import traceback

        logger.error(f"Traceback: {traceback.format_exc()}")


# Custom stream wrapper to capture the full response while streaming
async def stream_wrapper(stream, background_tasks, task_args):
    """Wrapper to capture the full response while streaming to client."""
    import asyncio
    import traceback

    full_response = bytearray()
    chunk_count = 0
    accumulated_content = ""
    is_groq_model = task_args.get("is_groq_model", False) if task_args else False

    try:
        # Log the start of streaming
        logger.info(f"Stream started, yielding chunks as they arrive")
        if is_groq_model:
            logger.info("Using Groq-specific error handling for this stream")

        # For OpenAI streaming responses - properly yield each chunk immediately
        async for chunk in stream:
            try:
                chunk_count += 1

                # Get the raw chunk data from the API
                chunk_json = chunk.model_dump()

                # Log the raw chunk data periodically for debugging
                if chunk_count % 100 == 0 or chunk_count < 3:
                    logger.debug(
                        f"Chunk #{chunk_count} raw data: {json.dumps(chunk_json)[:200]}..."
                    )

                # Format exactly as expected by SSE protocol and OpenAI standards
                chunk_data = f"data: {json.dumps(chunk_json)}\n\n"
                chunk_bytes = chunk_data.encode("utf-8")

                # Store the full response for saving to the database later
                full_response.extend(chunk_bytes)

                # Extract content for logging if available - with additional null checks
                if "choices" not in chunk_json:
                    logger.debug(f"Chunk #{chunk_count} has no 'choices' field")
                elif not chunk_json["choices"]:
                    logger.debug(f"Chunk #{chunk_count} has empty 'choices' array")
                else:
                    # Add null check before accessing choices[0]
                    choice = chunk_json["choices"][0]
                    if choice is None:
                        logger.debug(f"Chunk #{chunk_count} has None as first choice")
                    elif "delta" not in choice:
                        logger.debug(
                            f"Chunk #{chunk_count} has no 'delta' field in first choice"
                        )
                    elif choice["delta"] is None:
                        logger.debug(f"Chunk #{chunk_count} has None for 'delta'")
                    elif (
                        "content" in choice["delta"]
                        and choice["delta"]["content"] is not None
                    ):
                        content = choice["delta"]["content"]
                        accumulated_content += content

                        # Log first few chunks and periodically after that
                        if chunk_count <= 3 or chunk_count % 20 == 0:
                            logger.info(
                                f"Chunk #{chunk_count}: '{content}' - Accumulated: {len(accumulated_content)} chars"
                            )

                # Log every 10th chunk to avoid excessive logging
                if chunk_count % 10 == 0:
                    logger.debug(
                        f"Streaming chunk #{chunk_count}, total size so far: {len(full_response)} bytes"
                    )

                # Yield the raw chunk immediately and allow event loop to process before continuing
                yield chunk_bytes

                # Use sleep(0) to ensure the event loop has a chance to flush the response
                # This can help with buffering issues at the framework level
                await asyncio.sleep(0)
            except Exception as inner_e:
                logger.error(
                    f"Error processing individual chunk #{chunk_count}: {str(inner_e)}"
                )
                logger.error(
                    f"Chunk processing error traceback: {traceback.format_exc()}"
                )
                # Continue with next chunk rather than aborting the whole stream
                continue

        logger.info(
            f"Stream completed. Total chunks: {chunk_count}, total size: {len(full_response)} bytes"
        )
        logger.debug(
            f"Final accumulated content length: {len(accumulated_content)} characters"
        )

        # After stream completes, save the message to conversation
        if (
            task_args
            and "conversation_id" in task_args
            and "user_message_id" in task_args
        ):
            try:
                background_tasks.add_task(
                    save_streamed_message,
                    task_args["conversation_id"],
                    task_args["user_message_id"],
                    task_args["model_name"],
                    bytes(full_response),
                )
                logger.debug("Added save_streamed_message task to background tasks")
            except Exception as task_e:
                logger.error(f"Error adding save_streamed_message task: {str(task_e)}")
                logger.error(f"Task error traceback: {traceback.format_exc()}")
    except Exception as e:
        logger.error(f"Error in stream wrapper: {str(e)}")
        logger.error(f"Stream error traceback: {traceback.format_exc()}")
        import re

        # Check if this is a Groq error or we've identified it as a Groq model
        is_groq_exception = re.search(r"GroqException", str(e)) or is_groq_model

        # For Groq exceptions, we still want to save the message if we have chunks
        if is_groq_exception and len(full_response) > 0:
            logger.debug(
                f"Got Groq-related exception after receiving {chunk_count} chunks: WILL SAVE AND IGNORE"
            )

            # Save the message to conversation if we have task args and chunks
            if (
                task_args
                and "conversation_id" in task_args
                and "user_message_id" in task_args
                and chunk_count > 0
            ):
                try:
                    background_tasks.add_task(
                        save_streamed_message,
                        task_args["conversation_id"],
                        task_args["user_message_id"],
                        task_args["model_name"],
                        bytes(full_response),
                    )
                    logger.debug(
                        "Added save_streamed_message task to background tasks after Groq exception"
                    )
                except Exception as task_e:
                    logger.error(
                        f"Error adding save_streamed_message task after Groq exception: {str(task_e)}"
                    )
                    logger.error(
                        f"Post-Groq-exception task error traceback: {traceback.format_exc()}"
                    )

            # Instead of just returning, send a special completion message to the frontend
            # This will indicate that the response is complete despite the error
            # Create a completion JSON that looks like a normal completion message
            completion_json = {
                "id": f"chatcmpl-{uuid.uuid4()}",
                "object": "chat.completion.chunk",
                "created": int(time.time()),
                "model": task_args.get("model_name", "unknown"),
                "choices": [
                    {"index": 0, "delta": {"content": None}, "finish_reason": "stop"}
                ],
            }
            completion_message = f"data: {json.dumps(completion_json)}\n\n".encode(
                "utf-8"
            )
            yield completion_message

            # Also yield a special "DONE" message to properly close the stream
            yield b"data: [DONE]\n\n"
            return
        # For other exceptions, yield an error message
        error_json = json.dumps({"error": str(e)})
        error_message = f"data: {error_json}\n\n".encode("utf-8")
        yield error_message


# Create a request model for the chat endpoint
class ChatRequest(BaseModel):
    messages: List[Dict[str, str]]
    stream: bool = Field(default=False)
    params: Optional[Dict[str, Any]] = None
    conversation_id: Optional[str] = None


@router.post("/{model_name}/generate")
async def chat(
    model_name: str,
    background_tasks: BackgroundTasks,
    request: ChatRequest = Body(...),
    current_user: User = Depends(get_current_user),
):
    """Generate a response from a model using OpenAI API."""

    # Extract parameters from the request body
    messages = request.messages
    stream = request.stream
    params = request.params
    conversation_id = request.conversation_id

    logger.info(
        f"Processing request with stream={stream}, conversation_id={conversation_id}"
    )

    # Get the model from the database
    model = await LLMModel.find_one(LLMModel.display_name == model_name)
    logger.info(f"Model: {model}")
    if not model:
        logger.error(f"Model {model_name} not found")
        available_models = await LLMModel.find_all()
        logger.info(f"Available models: {available_models}")
        raise HTTPException(status_code=404, detail="Model not found")

    # Check if this is a Groq model (for special handling)
    is_groq_model = False
    if model.provider and model.provider.lower() == "groq":
        is_groq_model = True
        logger.info(f"Detected Groq model: {model_name}")

    # Validate conversation_id if provided
    conversation = None
    if conversation_id:
        try:
            # Use find_one() instead of get() to properly fetch the full document
            conversation = await Conversation.find_one(
                Conversation.id == UUID4(conversation_id),
                fetch_links=True,
            ).find_one(Conversation.user.id == current_user.id, fetch_links=True)

            # Then check if the conversation belongs to the current user
            if conversation and str(conversation.user.id) != str(current_user.id):
                logger.error(
                    f"Conversation {conversation_id} does not belong to user {current_user.id}"
                )
                raise HTTPException(
                    status_code=404,
                    detail="Conversation not found",
                )
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid conversation ID: {str(e)}",
            )

    # Track the user message ID if we need to store in conversation
    user_message_id = None
    if conversation and len(messages) > 0:
        # Get the last user message which we'll store
        last_message = messages[-1]
        if last_message.get("role") == "user":
            # Store the user message in the conversation
            user_message = await conversation.add_user_message(
                last_message.get("content", "")
            )
            user_message_id = user_message.id

    # Create request parameters
    request_params = {
        "model": model_name,
        "messages": messages,
        "stream": stream,
    }

    # Add any additional parameters from the params object
    if params:
        # Add each parameter individually instead of passing params as an object
        request_params.update(params)

    logger.info(f"Request parameters: {request_params}")

    # Initialize OpenAI client with user's auth token
    # Set timeout and max_retries for better streaming performance
    # If we're using LiteLLM, set the base URL
    client = AsyncOpenAI(
        api_key=current_user.auth_token,
        base_url=LITELLM_URL.rstrip("/") + "/v1",
        timeout=120.0,  # Increased timeout for longer streaming sessions
        max_retries=2,  # Limit retries to avoid hanging
    )
    logger.info(f"Using LiteLLM URL: {LITELLM_URL}")

    # Log the model being used and streaming mode
    logger.info(f"Generating response using model: {model_name}, streaming: {stream}")

    if stream:
        logger.info("Using streaming mode for response generation")
        # Explicitly ensure streaming parameter is set
        request_params["stream"] = True

    try:
        if stream:
            # For streaming responses, ensure we're using the stream parameter
            request_params["stream"] = True
            request_params["stream_options"] = {"include_usage": True}

            # Log if this is a Groq model for special handling
            if is_groq_model:
                logger.info("Detected Groq model, preparing for special error handling")

            # Remove the unnecessary completion_chunk_size code
            logger.info(f"Streaming setup complete. Request params: {request_params}")

            # Call the OpenAI API with streaming enabled
            stream_response = await client.chat.completions.create(**request_params)
            logger.info("OpenAI API streaming connection established")

            if conversation and user_message_id:
                task_args = {
                    "conversation_id": str(conversation.id),
                    "user_message_id": user_message_id,
                    "model_name": model_name,
                    "is_groq_model": is_groq_model,
                }
                # Use text/event-stream for SSE streaming with no buffering
                logger.info("Returning streaming response with conversation saving")
                return StreamingResponse(
                    stream_wrapper(stream_response, background_tasks, task_args),
                    media_type="text/event-stream",
                    headers={
                        "Cache-Control": "no-cache",
                        "Connection": "keep-alive",
                        "Transfer-Encoding": "chunked",
                        "X-Accel-Buffering": "no",  # Disable Nginx buffering if present
                    },
                )
            else:
                # If no conversation to save to, just stream the response
                logger.info("Returning streaming response without conversation saving")
                return StreamingResponse(
                    stream_wrapper(stream_response, background_tasks, {}),
                    media_type="text/event-stream",
                    headers={
                        "Cache-Control": "no-cache",
                        "Connection": "keep-alive",
                        "Transfer-Encoding": "chunked",
                        "X-Accel-Buffering": "no",  # Disable Nginx buffering if present
                    },
                )
        else:
            # For non-streaming responses
            response = await client.chat.completions.create(**request_params)

            # Convert response to dict for consistent return format
            result = response.model_dump()

            # If we have a conversation and the API call was successful, save the assistant message
            if (
                conversation
                and user_message_id
                and "choices" in result
                and len(result["choices"]) > 0
            ):
                try:
                    content = result["choices"][0]["message"]["content"]
                    # Get token count from the response
                    token_count = result.get("usage", {}).get("completion_tokens", 0)

                    # Add the assistant message to the conversation
                    await conversation.add_assistant_message(
                        content=content,
                        model_id=model_name,
                        parent_message_id=user_message_id,
                        token_count=token_count,
                    )
                except Exception as e:
                    logger.error(f"Error saving assistant message to conversation: {e}")
                    # Continue to return response even if saving fails

            return result
    except Exception as e:
        logger.error(f"Error calling OpenAI API: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error generating response: {str(e)}",
        )
