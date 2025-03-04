"""MongoDB User Model for Chatbot.  """

from datetime import datetime
from beanie import Document, Indexed
import httpx
from pydantic import UUID4, BaseModel

from typing import Annotated
import bcrypt
import os
from dotenv import load_dotenv

load_dotenv(override=True)

INTERNAL_API_URL = os.getenv("INTERNAL_API_URL")
LITELLM_URL = os.getenv("LITELLM_URL")
LITELLM_MASTER_KEY = os.getenv("LITELLM_MASTER_KEY")


class UserCreate(BaseModel):
    username: str
    name: str
    password: str


class User(Document):
    username: Annotated[str, Indexed(unique=True)]
    name: str
    password: str
    created_at: datetime
    auth_token: str

    @classmethod
    async def create_user(cls, user: UserCreate) -> "User":
        """Create a new user."""
        hashed_password = bcrypt.hashpw(
            user.password.encode("utf-8"), bcrypt.gensalt()
        ).decode("utf-8")

        # Get the LiteLLM API URL
        litellm_url = os.getenv("LITELLM_URL")
        if not litellm_url:
            raise ValueError("LITELLM_URL environment variable is not set")

        # Get auth token from litellm
        try:
            async with httpx.AsyncClient(
                base_url=litellm_url,
                headers={"Authorization": f"Bearer {LITELLM_MASTER_KEY}"},
                timeout=10.0,  # 10 second timeout
            ) as client:
                response = await client.post(
                    "/key/generate",
                    json={
                        "user_id": user.username,
                    },
                )

                if response.status_code != 200:
                    error_message = f"Failed to generate auth token: {response.text}"
                    raise ValueError(error_message)

                auth_token = response.json()["token"]
        except httpx.RequestError as e:
            # Handle timeout and connection errors
            raise ValueError(f"Could not connect to LiteLLM service: {str(e)}")
        except Exception as e:
            raise ValueError(f"Error generating auth token: {str(e)}")

        return cls(
            username=user.username,
            name=user.name,
            password=hashed_password,
            created_at=datetime.now(),
            auth_token=auth_token,
        )

    def verify_password(self, plain_password: str) -> bool:
        return bcrypt.checkpw(
            plain_password.encode("utf-8"), self.password.encode("utf-8")
        )
