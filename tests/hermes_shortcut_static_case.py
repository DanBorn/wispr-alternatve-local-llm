#!/usr/bin/env python3
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = (ROOT / "app/Sources/AppRuntime.swift").read_text(encoding="utf-8")
HOTKEYS = (ROOT / "app/Sources/Config/HotkeysConfig.swift").read_text(encoding="utf-8")
APP_CONFIG = (ROOT / "app/Sources/Config/AppConfig.swift").read_text(encoding="utf-8")
WIZARD = (ROOT / "app/Sources/CLI/ConfigWizard.swift").read_text(encoding="utf-8")
HERMES = (ROOT / "app/Sources/HermesAgentRunner.swift").read_text(encoding="utf-8")
CONFIG = json.loads((ROOT / "config/config.json").read_text(encoding="utf-8"))


def main() -> int:
    checks = [
        ("enum ControlOptionMode" in APP_CONFIG and "case hermes" in APP_CONFIG, "config must expose the Hermes Control + Option mode"),
        ('case controlOptionMode = "control_option_mode"' in APP_CONFIG, "config key control_option_mode is missing"),
        ("enabled" not in CONFIG.get("hermes_agent", {}), "checked-in config must not write legacy hermes_agent.enabled"),
        (CONFIG.get("control_option_mode") == "dump", "repository default must remain Markdown Dump"),
        ("Choose Control + Option mode" in WIZARD and "Hermes Agent — one spoken instruction" in WIZARD, "onboarding must offer one-segment Hermes"),
        ("RecordingRoutePolicy.isOneSegmentHermes" in RUNTIME and "mode: options.config.controlOptionMode" in RUNTIME, "runtime must route Control + Option to Hermes by config"),
        ("stopAndRunHermesAgent(screenshotTasks: screenshotTasks)" in RUNTIME, "Hermes must receive the first-segment screenshot tasks"),
        ("enqueueHermesAgentJob" in RUNTIME and "hermesJobQueue" in RUNTIME, "Hermes jobs must remain serialized outside transcription"),
        ("imageURLs: imageURLs" in RUNTIME and "hermesRunner.run" in RUNTIME, "ordered images must reach HermesAgentRunner"),
        ("nativeImageCommands" in HERMES and 'return "/image \\\"\\(escapedPath)\\\""' in HERMES, "Hermes must use native /image attachments"),
        ("for command in Self.nativeImageCommands(for: imageURLs)" in HERMES, "Hermes must attach every image in order"),
        ("try pasteAndSubmitInForegroundTerminal(prompt)" in HERMES, "Hermes prompt must be submitted after attachments"),
        ('tell application "Terminal"' in HERMES and 'tell process "Terminal"' in HERMES, "Hermes must use the visible Terminal session"),
        ('"sessions", "export"' in HERMES and '"--session-id"' in HERMES, "Hermes result must come from the exact visible session"),
        ("activateOriginalTargetIfPossible" in RUNTIME, "Hermes result must return to the original app when possible"),
        ('provider: "Hermes"' in RUNTIME and "retainFailedInteraction" in RUNTIME, "Hermes failures must retain transcript and images"),
        ("clearFailedCommandTurnAfterSuccess()" in RUNTIME, "successful Hermes delivery must clear retained failure state"),
        ("validateVoiceSessionID" in HERMES and "removeVoiceSessionState" in HERMES, "stale persisted Hermes session IDs must be rejected and removed"),
        ("Self.isValidSessionExport(stdout)" in HERMES, "session validation must reject Hermes' exit-zero Session not found response"),
        ("expectedSessionID" in HERMES and "state.sessionID == expectedSessionID" in HERMES, "Terminal tab reuse must match the validated Hermes session ID"),
        ('currentInteractiveSessionMarker(sessionID: sessionID)' in HERMES and '\\(sessionID ?? "named")' in HERMES, "visible Terminal markers must include the concrete Hermes session ID"),
        ("--test-hermes-instruction" in (ROOT / "app/Sources/CLI/Options.swift").read_text(encoding="utf-8"), "CLI must expose a reproducible visible Hermes text test"),
        ("runHermesInstructionTest" in RUNTIME, "Hermes CLI test must call the real visible runner"),
        ("recordingHermesInstruction" not in HOTKEYS, "old two-segment Hermes recording state must be removed"),
        ("isHermesAgentContinuationPressed" not in HOTKEYS, "old Command-first Hermes gesture must be removed"),
        ("scheduleHermesContinuationConfirmation" not in RUNTIME, "old Hermes continuation timer must be removed"),
    ]

    failed = False
    for passed, message in checks:
        if not passed:
            print(f"Hermes shortcut regression: {message}", file=sys.stderr)
            failed = True
    if failed:
        return 1
    print("Hermes shortcut static checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
