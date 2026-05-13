from app.models.response_models import NormalizedMessage


QUERY_KEYWORDS = {
    "complaint": [
        "not working",
        "broken",
        "issue",
        "problem",
        "complaint",
        "dirty",
        "bad",
        "leak",
        "smell",
        "noise",
        "ac not working",
        "wifi not working",
    ],
    "pre_sales_availability": [
        "available",
        "availability",
        "vacant",
        "free on",
    ],
    "pre_sales_pricing": [
        "price",
        "pricing",
        "rate",
        "cost",
        "tariff",
        "charges",
    ],
    "post_sales_checkin": [
        "wifi",
        "wi-fi",
        "password",
        "check in",
        "check-in",
        "checkin",
        "address",
        "location",
        "entry",
        "lockbox",
    ],
    "special_request": [
        "airport pickup",
        "pickup",
        "pick up",
        "extra bed",
        "decorate",
        "decoration",
        "cab",
        "transport",
    ],
}


def classify_query(message_text: str) -> str:
    normalized_text = message_text.strip().lower()

    for query_type, keywords in QUERY_KEYWORDS.items():
        if any(keyword in normalized_text for keyword in keywords):
            return query_type

    return "general_enquiry"


def apply_query_classification(message: NormalizedMessage) -> NormalizedMessage:
    query_type = classify_query(message.message_text)
    return message.model_copy(update={"query_type": query_type})
