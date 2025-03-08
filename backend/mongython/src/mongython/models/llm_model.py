from typing import Dict, Optional, Any, Annotated, List
from datetime import datetime
from pydantic import BaseModel, Field
from beanie import Document, Indexed


class ModelCapabilities(BaseModel):
    """Capabilities of an LLM model"""

    supports_system_messages: Optional[bool] = None
    supports_vision: Optional[bool] = None
    supports_function_calling: Optional[bool] = None
    supports_tool_choice: Optional[bool] = None
    supports_streaming: Optional[bool] = None
    supports_response_format: Optional[bool] = None
    supports_assistant_prefill: Optional[bool] = None
    supports_prompt_caching: Optional[bool] = None
    supports_audio_input: Optional[bool] = None
    supports_audio_output: Optional[bool] = None
    supports_pdf_input: Optional[bool] = None
    supports_embedding_image_input: Optional[bool] = None
    supports_response_schema: Optional[bool] = None


class LLMModel(Document):
    """Metadata for LLM models"""

    model_id: Annotated[
        str, Indexed(unique=True)
    ]  # Unique identifier (from litellm model_info.id)
    display_name: str  # User-friendly name (from litellm model_name)
    provider: str  # OpenAI, Anthropic, Ollama, etc.
    provider_model_id: (
        str  # The actual model ID used with the provider (from litellm_params.model)
    )

    # Token information
    max_input_tokens: Optional[int] = None
    max_output_tokens: Optional[int] = None

    # Pricing (in USD)
    input_price_per_token: float = 0.0  # Price per token
    output_price_per_token: float = 0.0  # Price per token

    # Capabilities
    capabilities: ModelCapabilities = Field(default_factory=ModelCapabilities)

    # Additional metadata from provider
    raw_provider_metadata: Optional[Dict[str, Any]] = None
    supported_openai_params: Optional[List[str]] = None

    # API base URL (if applicable)
    api_base: Optional[str] = None

    # Mode of the model (e.g., "chat")
    mode: Optional[str] = None

    # When this model was last synced
    last_synced: datetime = Field(default_factory=datetime.now)

    class Settings:
        name = "llm_models"

    @classmethod
    def extract_provider_from_name(cls, model_name: str) -> str:
        """Extract provider from model name using the specified rules"""
        if "/" in model_name:
            provider, _ = model_name.split("/", 1)
            if provider in ["ollama_chat", "ollama"]:
                return "Ollama"
            return provider.capitalize()

        # No provider prefix, try to infer from name
        if model_name.startswith("gpt-"):
            return "OpenAI"
        if model_name.startswith("claude-"):
            return "Anthropic"
        if "llama" in model_name.lower():
            return "Meta"

        # Default fallback
        return "Unknown"

    @classmethod
    async def from_litellm_info(cls, model_info: Dict[str, Any]) -> "LLMModel":
        """Create a model from LiteLLM model info response"""
        model_name = model_info.get("model_name", "")
        info = model_info.get("model_info", {})
        litellm_params = model_info.get("litellm_params", {})

        # Extract provider from model info or litellm_params
        provider = "Unknown"
        provider_model_id = litellm_params.get("model", "")

        if "litellm_provider" in info:
            provider = info["litellm_provider"].capitalize()
        elif provider_model_id:
            provider = cls.extract_provider_from_name(provider_model_id)

        # Create capabilities object
        capabilities = ModelCapabilities(
            supports_system_messages=info.get("supports_system_messages", False),
            supports_vision=info.get("supports_vision", False),
            supports_function_calling=info.get("supports_function_calling", False),
            supports_tool_choice=info.get("supports_tool_choice", False),
            supports_streaming=info.get("supports_native_streaming", True),
            supports_response_format=info.get("supports_response_format", False),
            supports_assistant_prefill=info.get("supports_assistant_prefill", False),
            supports_prompt_caching=info.get("supports_prompt_caching", False),
            supports_audio_input=info.get("supports_audio_input", False),
            supports_audio_output=info.get("supports_audio_output", False),
            supports_pdf_input=info.get("supports_pdf_input", False),
            supports_embedding_image_input=info.get(
                "supports_embedding_image_input", False
            ),
            supports_response_schema=info.get("supports_response_schema", False),
        )

        # Create the model
        return cls(
            model_id=info.get("id", model_name),  # Use the unique ID from model_info
            display_name=model_name,  # Use model_name as display name
            provider=provider,
            provider_model_id=provider_model_id,
            # Token information
            max_input_tokens=info.get("max_input_tokens", None),
            max_output_tokens=info.get("max_output_tokens", None),
            # Pricing
            input_price_per_token=info.get("input_cost_per_token", 0.0),
            output_price_per_token=info.get("output_cost_per_token", 0.0),
            # Capabilities
            capabilities=capabilities,
            # Mode
            mode=info.get("mode", "chat"),
            # API base
            api_base=litellm_params.get("api_base"),
            # Supported params
            supported_openai_params=info.get("supported_openai_params"),
            # Original data
            raw_provider_metadata=model_info,
        )
