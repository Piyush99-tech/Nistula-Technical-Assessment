from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


MessageSource = Literal["whatsapp", "booking_com", "airbnb", "instagram", "direct"]


class IncomingMessageRequest(BaseModel):
    source: MessageSource = Field(
        ...,
        description="Platform where the guest message originated.",
    )
    guest_name: str = Field(
        ...,
        min_length=1,
        description="Name of the guest who sent the message.",
    )
    message: str = Field(
        ...,
        min_length=1,
        description="Original message text received from the guest.",
    )
    timestamp: datetime = Field(
        ...,
        description="Timestamp when the message was received.",
    )
    booking_ref: str | None = Field(
        default=None,
        description="Booking reference if available for the guest.",
    )
    property_id: str = Field(
        ...,
        min_length=1,
        description="Unique property identifier.",
    )

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "source": "whatsapp",
                "guest_name": "Rahul Sharma",
                "message": "Is the villa available from April 20 to 24?",
                "timestamp": "2026-05-05T10:30:00Z",
                "booking_ref": "NIS-2024-0891",
                "property_id": "villa-b1",
            }
        }
    )
