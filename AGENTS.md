# AGENTS.md

bada is a macOS menu bar app for Korean dictation. A shortcut opens a small capsule under the caret, the microphone is transcribed locally by Qwen3-ASR (MLX) running in a Python child process, an optional OpenAI-compatible LLM polishes the text, and the result is pasted at the caret.

## Layout

| Path | What |
| --- | --- |
| `Sources/Bada/App` | Entry point, app delegate, menu bar, hidden main menu |
| `Sources/Bada/Dictation` | The dictation flow, caret lookup, pasting |
| `Sources/Bada/Audio` | Microphone capture, resampling, level meter |
| `Sources/Bada/Speech` | The speech engine child process |
| `Sources/Bada/Polish` | LLM prompt and Chat Completions client |
| `Sources/Bada/HUD` | The floating capsule |
| `Sources/Bada/Settings` | Settings window |
| `Sources/Bada/Support` | Preferences, shortcuts, permissions, paths, logging, colors |
| `engine/` | `engine.py` and its pinned requirements |
| `scripts/` | `build.sh` (build, `--install`) and `sign.sh` |

## Build

```sh
scripts/build.sh            # build/Bada.app
scripts/build.sh --install  # /Applications/Bada.app, then open it
swift build                 # quick compile check
```

Logs: `~/Library/Logs/Bada/bada.log` and `engine.log`.

## Rules

- Audio never leaves the Mac. Only the transcript and the vocabulary go to the LLM the user configured.
- Never log, print or commit transcripts, API keys, endpoints or machine-specific paths.
- UI text is Korean; code, comments and commit messages are English.
- Apple frameworks only on the Swift side. Python dependencies stay pinned in `engine/requirements.txt`.
- `swift build` must stay free of warnings.
- The HUD panel must never take focus: typing stays in the user's app.
- Check UI changes in light and dark mode, and the capsule over light and dark backgrounds.
- Permissions only work in the signed app from `scripts/build.sh`, not in a bare `swift build` binary.
