"""Base document class for MongoDB models."""

from beanie import Document
from pydantic import UUID4, Field
import uuid

class BaseDocument(Document):
    """Base document class with common settings and functionality."""
    
    # MongoDB id field using UUID4
    id: UUID4 = Field(default_factory=uuid.uuid4)
    
    class Settings:
        use_state_management = True
        use_objectid_ids = False  # Using UUID4 instead of ObjectId 