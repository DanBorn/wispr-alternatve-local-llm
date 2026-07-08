#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BINARY = REPO_ROOT / "app" / ".build" / "debug" / "fluid-push-to-talk"
SOURCE = "Ja, genau, einfach mal so reingehauen."
COMMAND = "Bitte auf Englisch übersetzen."
MAX_ATTEMPTS = 3


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


def run_once(config_path: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            str(BINARY),
            "--config",
            str(config_path),
            "--test-command-information",
            SOURCE,
            "--test-command",
            COMMAND,
        ],
        check=False,
        capture_output=True,
        text=True,
        timeout=45,
    )


def validate(completed: subprocess.CompletedProcess[str]) -> bool:
    if completed.returncode != 0:
        return False

    command_index = completed.stdout.find(COMMAND)
    information_index = completed.stdout.find(SOURCE)
    if command_index == -1 or information_index == -1 or command_index > information_index:
        print("translation regression: LLM request did not put command before information", file=sys.stderr)
        return False

    result_lines = [
        line.removeprefix("[result] ").strip()
        for line in completed.stdout.splitlines()
        if line.startswith("[result] ")
    ]
    if not result_lines:
        print("translation regression: app did not print a [result] line", file=sys.stderr)
        return False

    content = result_lines[-1]
    if content == SOURCE:
        print("translation regression: model repeated the German source", file=sys.stderr)
        return False
    if "yes" not in content.lower():
        print("translation regression: expected an English translation containing 'yes'", file=sys.stderr)
        return False
    return True


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
    config.setdefault("debug", {})
    config["debug"]["log_llm_requests"] = True

    temp_dir = tempfile.TemporaryDirectory()
    config_path = Path(temp_dir.name) / "config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")

    last_completed = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        completed = run_once(config_path)
        last_completed = completed
        print(completed.stdout, end="")
        if completed.stderr:
            print(completed.stderr, end="", file=sys.stderr)
        if validate(completed):
            return 0
        if attempt < MAX_ATTEMPTS:
            print(f"translation regression: retrying live OpenAI-compatible command ({attempt + 1}/{MAX_ATTEMPTS})")
    if last_completed and last_completed.returncode != 0:
        return last_completed.returncode
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
