from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from app.models.request_models import MessageSource

QueryType = Literal[
    "pre_sales_availability",
    "pre_sales_pricing",
    "post_sales_checkin",
    "special_request",
    "complaint",
    "general_enquiry",
]

ActionType = Literal["auto_send", "agent_review", "escalate"]


class NormalizedMessage(BaseModel):
    message_id: str = Field(
        ...,
        description="System-generated unique message identifier.",
    )
    source: MessageSource = Field(
        ...,
        description="Platform where the guest message originated.",
    )
    guest_name: str = Field(
        ...,
        description="Name of the guest who sent the message.",
    )
    message_text: str = Field(
        ...,
        description="Normalized guest message text.",
    )
    timestamp: datetime = Field(
        ...,
        description="Timestamp of the incoming message.",
    )
    booking_ref: str | None = Field(
        default=None,
        description="Booking reference if available.",
    )
    property_id: str = Field(
        ...,
        description="Unique property identifier.",
    )
    query_type: QueryType | None = Field(
        default=None,
        description="Query type will be filled by the classifier step.",
    )


class WebhookMessageResponse(BaseModel):
    message_id: str = Field(
        ...,
        description="System-generated unique message identifier.",
    )
    query_type: QueryType = Field(
        ...,
        description="Detected guest query type.",
    )
    drafted_reply: str = Field(
        ...,
        description="Claude-generated guest reply draft.",
    )
    confidence_score: float = Field(
        ...,
        ge=0,
        le=1,
        description="System confidence score between 0 and 1.",
    )
    action: ActionType = Field(
        ...,
        description="Recommended workflow action based on confidence and query type.",
    )

    model_config = ConfigDict(
        json_schema_extra={
            "example": {
                "message_id": "4e6c103a-436d-4f64-b8e8-b9d6ca1a8f4f",
                "query_type": "pre_sales_availability",
                "drafted_reply": "Hi Rahul! Great news - Villa B1 is available from April 20 to 24.",
                "confidence_score": 0.91,
                "action": "auto_send",
            }
        }
    )
