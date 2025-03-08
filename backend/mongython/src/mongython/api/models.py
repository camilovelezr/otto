"""API endpoints for managing LLM models."""

import logging
import os
from typing import List, Optional, Dict, Any
from fastapi import APIRouter, HTTPException, Depends, Query, status
from pydantic import BaseModel
import httpx

from mongython.models.llm_model import LLMModel
from mongython.api.users import get_current_user
from mongython.models.user import User
from dotenv import load_dotenv, find_dotenv

load_dotenv(find_dotenv())

router = APIRouter(
    prefix="/models",
    tags=["models"],
)

logger = logging.getLogger(__name__)

LITELLM_URL = os.getenv("LITELLM_URL")
logger.info(f"LITELLM_URL: {LITELLM_URL}")


class ModelUpdateRequest(BaseModel):
    max_input_tokens: Optional[int] = None
    max_output_tokens: Optional[int] = None
    max_total_tokens: Optional[int] = None
    input_price_per_token: Optional[float] = None
    output_price_per_token: Optional[float] = None


@router.get("/list", response_model=List[LLMModel])
async def get_models(
    provider: Optional[str] = Query(None, description="Filter by provider")
):
    """Get a list of available LLM models."""
    query = {}
    if provider:
        query["provider"] = provider

    models = await LLMModel.find(query).to_list()
    return models


@router.get("/{model_id}", response_model=LLMModel)
async def get_model(model_id: str):
    """Get details for a specific model."""
    model = await LLMModel.find_one(LLMModel.model_id == model_id)
    if not model:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Model {model_id} not found",
        )
    return model


@router.put("/{model_id}", response_model=LLMModel)
async def update_model(model_id: str, update_data: ModelUpdateRequest):
    """Update model metadata."""
    model = await LLMModel.find_one(LLMModel.model_id == model_id)
    if not model:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Model {model_id} not found",
        )

    # Update only the fields that are provided
    update_dict = update_data.dict(exclude_unset=True, exclude_none=True)
    for key, value in update_dict.items():
        setattr(model, key, value)

    await model.save()
    return model


@router.post("/sync", response_model=List[LLMModel])
async def sync_models_from_litellm():
    """Sync model metadata from LiteLLM API

    Args:
        user_id: Optional user ID to use their auth token for the request
    """
    # Use internal API call instead of direct LiteLLM call

    # Prepare headers with master key for LiteLLM access
    from mongython.models.user import LITELLM_MASTER_KEY

    headers = {"Authorization": f"Bearer {LITELLM_MASTER_KEY}"}

    try:
        async with httpx.AsyncClient(base_url=LITELLM_URL) as client:
            response = await client.get(
                "/v1/model/info",
                headers=headers,
                timeout=60.0,
            )

            if response.status_code != 200:
                raise HTTPException(
                    status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                    detail=f"Failed to get model info from LiteLLM: {response.text}",
                )

            model_data = response.json()
            logger.info(f"Model data: {model_data}")
            models = []

            # Process each model
            for model_info in model_data.get("data", []):
                # Create new model using from_litellm_info
                new_model = await LLMModel.from_litellm_info(model_info)

                # Check if model already exists
                existing_model = await LLMModel.find_one(
                    LLMModel.model_id == new_model.model_id
                )

                if existing_model:
                    # Update existing model fields
                    for field in existing_model.model_fields:
                        if field != "id" and hasattr(new_model, field):
                            setattr(existing_model, field, getattr(new_model, field))

                    await existing_model.save()
                    models.append(existing_model)
                else:
                    # Save new model
                    await new_model.save()
                    models.append(new_model)

            return models

    except httpx.RequestError as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error connecting to LiteLLM: {str(e)}",
        )
    except Exception as e:
        logger.error(f"Error syncing models: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error syncing models: {str(e)}",
        )


@router.delete("/all", status_code=status.HTTP_204_NO_CONTENT)
async def delete_all_models():
    """
    Delete all models from the database.
    This endpoint is intentionally not protected to allow external systems to call it.
    """
    try:
        # Delete all documents in the LLMModel collection
        await LLMModel.delete_all()
        return {"detail": "All models have been deleted"}
    except Exception as e:
        logger.error(f"Error deleting models: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error deleting models: {str(e)}",
        )
