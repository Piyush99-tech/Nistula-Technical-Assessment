from pathlib import Path

import httpx

from app.config.settings import settings
from app.models.response_models import NormalizedMessage


class ClaudeConfigurationError(Exception):
    pass


class ClaudeServiceError(Exception):
    pass


PROMPT_TEMPLATE_PATH = Path(__file__).resolve().parents[1] / "prompts" / "claude_prompt.txt"


def _safe_for_format(value: str) -> str:
    """So guest text or context with { } does not break str.format()."""
    return value.replace("{", "{{").replace("}", "}}")


def build_claude_prompt(message: NormalizedMessage, property_context: str) -> str:
    prompt_template = PROMPT_TEMPLATE_PATH.read_text(encoding="utf-8")

    return prompt_template.format(
        guest_name=_safe_for_format(message.guest_name),
        source=str(message.source),
        booking_ref=_safe_for_format(message.booking_ref or "Not provided"),
        property_id=_safe_for_format(message.property_id),
        query_type=str(message.query_type or "general_enquiry"),
        message_text=_safe_for_format(message.message_text),
        property_context=_safe_for_format(property_context),
    )


def _anthropic_error_detail(response: httpx.Response) -> str:
    try:
        data = response.json()
        err = data.get("error") if isinstance(data, dict) else None
        if isinstance(err, dict) and err.get("message"):
            return str(err["message"])
        if isinstance(err, str):
            return err
    except ValueError:
        pass
    text = response.text or ""
    return text[:800] if text else "(empty body)"


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
        detail = _anthropic_error_detail(exc.response)
        raise ClaudeServiceError(
            f"Claude API returned {exc.response.status_code}: {detail}",
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
