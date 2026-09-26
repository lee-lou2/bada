# AGENTS.md

mal2geul (말2글, "speech to writing") is a macOS menu bar app for Korean dictation. A shortcut opens a small capsule under the caret, the microphone is transcribed locally by Qwen3-ASR (MLX) running in a Python child process, an optional OpenAI-compatible LLM polishes the text, and the result is pasted at the caret.

## Layout

| Path | What |
| --- | --- |
| `Sources/Mal2geul/App` | Entry point, app delegate, menu bar, hidden main menu |
| `Sources/Mal2geul/Dictation` | The dictation flow, caret lookup, pasting |
| `Sources/Mal2geul/Audio` | Microphone capture, resampling, level meter |
| `Sources/Mal2geul/Speech` | The speech engine child process |
| `Sources/Mal2geul/Polish` | LLM prompt and Chat Completions client |
| `Sources/Mal2geul/HUD` | The floating capsule |
| `Sources/Mal2geul/Settings` | Settings window |
| `Sources/Mal2geul/Support` | Preferences, shortcuts, permissions, paths, logging, colors |
| `engine/` | `engine.py`, `requirements.in`, and the hash-locked `requirements.txt` |
| `scripts/` | `build.sh` (build, `--install`, `--dmg`) and `sign.sh` |

## Build

```sh
scripts/build.sh            # build/말2글.app
scripts/build.sh --install  # /Applications/말2글.app, then open it
scripts/build.sh --dmg      # build/Mal2geul-<version>.dmg for a GitHub release
swift build                 # quick compile check
```

On first launch the app installs the speech engine into `~/Library/Application Support/Mal2geul/engine` (`EngineInstaller`: pinned uv → managed Python → `requirements.txt`). It reinstalls when the lock file changes. After editing `engine/requirements.in`, regenerate the lock with the command at its top.

Logs: `~/Library/Logs/Mal2geul/mal2geul.log` and `engine.log`.

## Releases

Bump `CFBundleShortVersionString` in `Resources/Info.plist`, run `scripts/build.sh --dmg`, and attach the DMG to a `vX.Y.Z` GitHub release. Sign every release with the same identity (`MAL2GEUL_SIGN_IDENTITY`, or the local one in `~/Library/Application Support/Mal2geul/signing`), otherwise users lose their Microphone and Accessibility permission on update.

## Rules

- Audio never leaves the Mac. Only the transcript and the vocabulary go to the LLM the user configured.
- Never log, print or commit transcripts, API keys, endpoints or machine-specific paths.
- UI text is Korean; code, comments and commit messages are English. The app is 말2글 in the UI and mal2geul (`Mal2geul` in type and file names) everywhere else.
- `Polisher.instructions` is English with Korean output on purpose. Keep it short: detailed rule lists make reasoning models deliberate much longer and slow dictation down; examples carry the behavior.
- Apple frameworks only on the Swift side. Python dependencies stay pinned in `engine/requirements.txt`.
- `swift build` must stay free of warnings.
- The HUD panel must never take focus: typing stays in the user's app.
- Check UI changes in light and dark mode, and the capsule over light and dark backgrounds.
- Permissions only work in the signed app from `scripts/build.sh`, not in a bare `swift build` binary.
