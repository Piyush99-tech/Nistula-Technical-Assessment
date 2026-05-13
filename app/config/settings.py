import os

from dotenv import load_dotenv


load_dotenv()


class Settings:
    app_name: str = "Nistula Technical Assessment API"
    claude_api_key: str = os.getenv("CLAUDE_API_KEY", "")
    claude_model: str = os.getenv("CLAUDE_MODEL", "claude-sonnet-4-20250514")
    claude_api_url: str = os.getenv(
        "CLAUDE_API_URL",
        "https://api.anthropic.com/v1/messages",
    )
    claude_max_tokens: int = int(os.getenv("CLAUDE_MAX_TOKENS", "250"))
    claude_timeout_seconds: float = float(
        os.getenv("CLAUDE_TIMEOUT_SECONDS", "30"),
    )


settings = Settings()
