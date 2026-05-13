from fastapi import APIRouter, HTTPException

from app.models.request_models import IncomingMessageRequest
from app.models.response_models import WebhookMessageResponse
from app.services.claude_service import (
    ClaudeConfigurationError,
    ClaudeServiceError,
    generate_draft_reply,
)
from app.services.classifier_service import apply_query_classification
from app.services.confidence_service import calculate_confidence_score, decide_action
from app.services.normalization_service import normalize_incoming_message
from app.services.property_service import (
    PropertyContextNotFoundError,
    get_property_context,
)


router = APIRouter(prefix="/webhook", tags=["webhook"])


@router.post("/message", response_model=WebhookMessageResponse)
async def receive_message(payload: IncomingMessageRequest) -> WebhookMessageResponse:
    normalized_message = normalize_incoming_message(payload)
    classified_message = apply_query_classification(normalized_message)
    query_type = classified_message.query_type or "general_enquiry"

    try:
        property_context = get_property_context(classified_message.property_id)
        drafted_reply = await generate_draft_reply(classified_message, property_context)
    except PropertyContextNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ClaudeConfigurationError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except ClaudeServiceError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    confidence_score = calculate_confidence_score(classified_message, drafted_reply)
    action = decide_action(query_type, confidence_score)

    return WebhookMessageResponse(
        message_id=classified_message.message_id,
        query_type=query_type,
        drafted_reply=drafted_reply,
        confidence_score=confidence_score,
        action=action,
    )
