"""Attach the user's shared admission control to the unmodified skill CLI.

The skill CLI owns argument handling, Image API operations and output decoding.
This adapter only supplies process-local configuration and guards each request.
It supports synchronous generate/edit; it never retries uncertain requests.
"""
import importlib.util
import os
from pathlib import Path
import sys
import tomllib


def main():
    home = Path(os.environ.get("CODEX_HOME", r"C:\Users\admin\.codex"))
    config = tomllib.loads((home / "config.toml").read_text(encoding="utf-8"))
    provider = config["model_providers"][config["model_provider"]]
    key = provider.get("experimental_bearer_token") or os.environ.get(provider.get("env_key", ""))
    if not key:
        raise SystemExit("Selected provider has no usable experimental_bearer_token/env_key credential.")
    base = provider["base_url"]
    os.environ["OPENAI_API_KEY"] = key
    os.environ["OPENAI_BASE_URL"] = base
    sys.path.insert(0, str(home / "tools"))
    from api_concurrency import guarded_call

    if len(sys.argv) < 2 or sys.argv[1] not in ("generate", "edit"):
        raise SystemExit("Use synchronous generate/edit. Async batch is intentionally unsupported.")
    if "--model" not in sys.argv and not any(arg.startswith("--model=") for arg in sys.argv):
        sys.argv.extend(["--model", "gpt-image-2.5-sunburst"])
    skill = home / "skills/.system/imagegen/scripts/image_gen.py"
    spec = importlib.util.spec_from_file_location("skill_imagegen_cli", skill)
    cli = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cli)
    original_factory = cli._create_client

    class Images:
        def __init__(self, original):
            self.original = original

        def generate(self, **kwargs):
            return guarded_call(key, lambda: self.original.generate(**kwargs))

        def edit(self, **kwargs):
            return guarded_call(key, lambda: self.original.edit(**kwargs))

    def configured_client():
        client = original_factory().with_options(max_retries=0)
        assert client.max_retries == 0, "SDK automatic retries must remain disabled"
        client.images = Images(client.images)
        return client

    cli._create_client = configured_client
    cli.main()


if __name__ == "__main__":
    main()
