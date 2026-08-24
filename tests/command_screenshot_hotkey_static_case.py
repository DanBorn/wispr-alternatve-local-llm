#!/usr/bin/env python3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
RUNTIME = REPO_ROOT / "app" / "Sources" / "AppRuntime.swift"
HOTKEYS = REPO_ROOT / "app" / "Sources" / "Config" / "HotkeysConfig.swift"


def main() -> int:
    runtime = RUNTIME.read_text(encoding="utf-8")
    hotkeys = HOTKEYS.read_text(encoding="utf-8")
    event_block = runtime[runtime.find("private extension HotkeyMonitor"):runtime.find("func isBluetoothModifierPressed")]
    capture_block = runtime[runtime.find("func captureCommandScreenshot"):runtime.find("private func handleBluetoothChordLocked")]
    continuation_block = runtime[runtime.find("private func confirmContinuation"):runtime.find("private func cancelPendingContinuation")]
    checks = [
        ("commandScreenshotKeyCode: CGKeyCode = 35" in runtime, "P screenshot hotkey must use macOS keycode 35"),
        ("struct PictureKeyLatch" in runtime and "commandScreenshotKeyLatch" in runtime, "P hotkey must use a physical-key latch"),
        ("keyboardEventAutorepeat" in event_block, "P hotkey must ignore autorepeat keyDown events"),
        ("case .keyDown" in event_block and "case .keyUp" in event_block, "P hotkey must handle and swallow keyDown plus keyUp"),
        ("return commandScreenshotKeyLatch.keyDown" in event_block, "P keyDown swallowing must follow latch ownership"),
        ("commandScreenshotKeyLatch.keyUp()" in event_block, "P keyUp must re-arm screenshot capture"),
        ("controller.captureCommandScreenshot()" in event_block, "physical P keyDown must request one screenshot"),
        ("func captureCommandScreenshot() -> Bool" in runtime, "P capture acceptance must synchronously reflect controller state"),
        ("maximumCommandScreenshots = 5" in runtime, "command screenshot capture must cap at five images"),
        ("guard screenshotTasks.count < maximumCommandScreenshots" in capture_block, "the sixth screenshot request must be ignored"),
        ("case let .recordingInformation(action, screenshotTasks)" in capture_block, "P must capture only during a first information recording"),
        ("RecordingRoutePolicy.supportsScreenshots(action: action)" in capture_block, "P must support paste and Control + Option recordings"),
        ("pasteHotkey.isPressed" in event_block and "dumpHotkey.isPressed" in event_block, "P must recognize both screenshot-capable chords"),
        ("screenshotTasks: [Task<URL?, Never>]" in hotkeys, "recording states must carry ordered screenshot tasks"),
        ("screenshotTasks: screenshotTasks" in continuation_block, "captured tasks must carry into command state"),
        ("captureCommandImageContext()" not in continuation_block, "transition to command recording must not capture automatically"),
        ("cleanupCommandScreenshotTasks" in runtime, "normal/error exits must clean captured screenshot tasks"),
        (runtime.count("cleanupCommandScreenshotTasks(") >= 3, "captured screenshots must be cleaned on dictation, command, and error paths"),
    ]
    failed = False
    for passed, message in checks:
        if not passed:
            print(f"command screenshot hotkey regression: {message}", file=sys.stderr)
            failed = True
    if failed:
        return 1
    print("command screenshot hotkey static checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
