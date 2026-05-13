from app.models.response_models import ActionType, NormalizedMessage


HIGH_SIGNAL_QUERY_TYPES = {
    "pre_sales_availability",
    "pre_sales_pricing",
    "post_sales_checkin",
    "special_request",
    "complaint",
}

FACTUAL_QUERY_TYPES = {
    "pre_sales_availability",
    "pre_sales_pricing",
    "post_sales_checkin",
    "special_request",
}

SEVERE_COMPLAINT_KEYWORDS = {
    "refund",
    "money back",
    "compensation",
    "legal",
    "lawyer",
    "fraud",
    "scam",
    "terrible",
    "horrible",
}


def contains_keyword(text: str, keywords: set[str]) -> bool:
    normalized_text = text.strip().lower()
    return any(keyword in normalized_text for keyword in keywords)


def calculate_confidence_score(
    message: NormalizedMessage,
    drafted_reply: str,
) -> float:
    score = 0.35

    if message.query_type in HIGH_SIGNAL_QUERY_TYPES:
        score += 0.15

    if len(message.message_text.split()) >= 4:
        score += 0.10

    if drafted_reply.strip():
        score += 0.15

    if message.booking_ref:
        score += 0.05

    if message.query_type in FACTUAL_QUERY_TYPES:
        score += 0.10

    if message.query_type == "general_enquiry":
        score -= 0.15

    if message.query_type == "complaint":
        score -= 0.25

    if contains_keyword(message.message_text, SEVERE_COMPLAINT_KEYWORDS):
        score -= 0.15

    if message.query_type == "complaint":
        score = min(score, 0.55)

    if message.query_type == "complaint" and contains_keyword(
        message.message_text,
        SEVERE_COMPLAINT_KEYWORDS,
    ):
        score = min(score, 0.40)

    score = max(0.0, min(score, 1.0))
    return round(score, 2)


def decide_action(query_type: str, confidence_score: float) -> ActionType:
    if query_type == "complaint" or confidence_score < 0.60:
        return "escalate"

    if confidence_score <= 0.85:
        return "agent_review"

    return "auto_send"
