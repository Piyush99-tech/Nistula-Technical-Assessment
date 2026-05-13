import os

from dotenv import load_dotenv


load_dotenv()


class Settings:
    app_name: str = "Nistula Technical Assessment API"
    # Strip whitespace/newlines — a trailing newline in .env breaks the model id and causes API 400s.
    claude_api_key: str = (os.getenv("CLAUDE_API_KEY") or "").strip()
    claude_model: str = (os.getenv("CLAUDE_MODEL") or "claude-sonnet-4-20250514").strip()
    claude_api_url: str = (os.getenv(
        "CLAUDE_API_URL",
        "https://api.anthropic.com/v1/messages",
    ) or "https://api.anthropic.com/v1/messages").strip()
    claude_max_tokens: int = int(os.getenv("CLAUDE_MAX_TOKENS", "250"))
    claude_timeout_seconds: float = float(
        os.getenv("CLAUDE_TIMEOUT_SECONDS", "30"),
    )


settings = Settings()
