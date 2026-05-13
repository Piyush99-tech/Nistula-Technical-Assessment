from pathlib import Path

import httpx

from app.config.settings import settings
from app.models.response_models import NormalizedMessage


class ClaudeConfigurationError(Exception):
    pass


class ClaudeServiceError(Exception):
    pass


PROMPT_TEMPLATE_PATH = Path(__file__).resolve().parents[1] / "prompts" / "claude_prompt.txt"


def build_claude_prompt(message: NormalizedMessage, property_context: str) -> str:
    prompt_template = PROMPT_TEMPLATE_PATH.read_text(encoding="utf-8")

    return prompt_template.format(
        guest_name=message.guest_name,
        source=message.source,
        booking_ref=message.booking_ref or "Not provided",
        property_id=message.property_id,
        query_type=message.query_type or "general_enquiry",
        message_text=message.message_text,
        property_context=property_context,
    )


async def generate_draft_reply(message: NormalizedMessage, property_context: str) -> str:
    if not settings.claude_api_key:
        raise ClaudeConfigurationError(
            "CLAUDE_API_KEY is missing. Add it to your .env file to generate replies.",
        )

    prompt = build_claude_prompt(message, property_context)

    headers = {
        "x-api-key": settings.claude_api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
    payload = {
        "model": settings.claude_model,
        "max_tokens": settings.claude_max_tokens,
        "messages": [{"role": "user", "content": prompt}],
    }

    try:
        async with httpx.AsyncClient(timeout=settings.claude_timeout_seconds) as client:
            response = await client.post(
                settings.claude_api_url,
                headers=headers,
                json=payload,
            )
            response.raise_for_status()
    except httpx.TimeoutException as exc:
        raise ClaudeServiceError("Claude API request timed out.") from exc
    except httpx.HTTPStatusError as exc:
        raise ClaudeServiceError(
            f"Claude API returned {exc.response.status_code}.",
        ) from exc
    except httpx.HTTPError as exc:
        raise ClaudeServiceError("Claude API request failed.") from exc

    data = response.json()
    text_blocks = [
        block.get("text", "").strip()
        for block in data.get("content", [])
        if block.get("type") == "text"
    ]
    drafted_reply = " ".join(block for block in text_blocks if block).strip()

    if not drafted_reply:
        raise ClaudeServiceError("Claude API returned an empty response.")

    return drafted_reply
