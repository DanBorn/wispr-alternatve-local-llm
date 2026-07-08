#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BINARY = REPO_ROOT / "app" / ".build" / "debug" / "fluid-push-to-talk"
INFORMATION = "The required token is OK."
COMMAND = "Return exactly the required token and nothing else."
MAX_LATENCY_SECONDS = 45.0


def hosted_llm_config() -> tuple[str, str, str, str]:
    if os.environ.get("COMMAND_LLM_API_KEY_ENV"):
        api_key_env = os.environ["COMMAND_LLM_API_KEY_ENV"]
    elif os.environ.get("CEREBRAS_API_KEY"):
        api_key_env = "CEREBRAS_API_KEY"
    else:
        api_key_env = "OPENAI_API_KEY"

    if api_key_env == "CEREBRAS_API_KEY":
        return (
            "cerebras",
            os.environ.get("CEREBRAS_BASE_URL", "https://api.cerebras.ai/v1"),
            os.environ.get("CEREBRAS_MODEL", "gemma-4-31b"),
            api_key_env,
        )

    return (
        "openai_compatible",
        os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1"),
        os.environ.get("OPENAI_MODEL", "gpt-5.4-mini"),
        api_key_env,
    )


def main() -> int:
    config = json.loads((REPO_ROOT / "config" / "config.json").read_text(encoding="utf-8"))
    provider, base_url, model, api_key_env = hosted_llm_config()
    config["prompt_config_file"] = str(REPO_ROOT / "config" / "promptConfig.json")
    config.setdefault("local_llm", {})
    config["local_llm"]["enabled"] = True
    config["local_llm"]["command_generation_enabled"] = True
    config["local_llm"]["provider"] = provider
    config["local_llm"]["endpoint"] = ""
    config["local_llm"]["base_url"] = base_url
    config["local_llm"]["model"] = model
    config["local_llm"]["api_key_env"] = api_key_env
    if provider == "cerebras":
        config["local_llm"]["temperature"] = 1
        config["local_llm"]["top_p"] = 0.95
        config["local_llm"]["max_tokens"] = 32768
        config["local_llm"]["image_context_enabled"] = True

    with tempfile.TemporaryDirectory() as temp_dir:
        config_path = Path(temp_dir) / "config.json"
        config_path.write_text(json.dumps(config), encoding="utf-8")

        started = time.monotonic()
        completed = subprocess.run(
            [
                str(BINARY),
                "--config",
                str(config_path),
                "--test-command-information",
                INFORMATION,
                "--test-command",
                COMMAND,
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=MAX_LATENCY_SECONDS,
        )
        elapsed = time.monotonic() - started

    print(completed.stdout, end="")
    if completed.stderr:
        print(completed.stderr, end="", file=sys.stderr)
    if completed.returncode != 0:
        return completed.returncode

    route_name = "Cerebras" if provider == "cerebras" else "OpenAI-compatible"
    expected_route = f"sending command LLM request to {route_name} {config['local_llm']['model']}"
    if expected_route not in completed.stdout:
        print("hosted command smoke regression: command route did not use configured provider", file=sys.stderr)
        return 1

    result_lines = [
        line.removeprefix("[result] ").strip()
        for line in completed.stdout.splitlines()
        if line.startswith("[result] ")
    ]
    if not result_lines:
        print("hosted command smoke regression: app did not print a [result] line", file=sys.stderr)
        return 1
    if result_lines[-1].strip().strip(".") != "OK":
        print(f"hosted command smoke regression: expected OK, got {result_lines[-1]!r}", file=sys.stderr)
        return 1

    print(f"hosted command LLM smoke completed in {elapsed:.2f}s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
