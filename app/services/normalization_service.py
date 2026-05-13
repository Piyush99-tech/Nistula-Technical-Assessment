from uuid import uuid4

from app.models.request_models import IncomingMessageRequest
from app.models.response_models import NormalizedMessage


def normalize_incoming_message(payload: IncomingMessageRequest) -> NormalizedMessage:
    return NormalizedMessage(
        message_id=str(uuid4()),
        source=payload.source,
        guest_name=payload.guest_name,
        message_text=payload.message,
        timestamp=payload.timestamp,
        booking_ref=payload.booking_ref,
        property_id=payload.property_id,
        query_type=None,
    )
