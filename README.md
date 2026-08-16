# AI-Agent

An Android-first AI coding agent built with Flutter and powered by NVIDIA NIM-compatible chat APIs.

## Features

- Chat-style coding agent UI
- NVIDIA API integration using the OpenAI-compatible `/v1/chat/completions` endpoint
- Configurable NVIDIA API key and model, stored locally on-device
- Attach/select project files for lightweight project context
- Markdown rendering for code and explanations
- GitHub Actions workflow that analyzes, tests, builds a release APK, and uploads it as an artifact

## NVIDIA setup

Create an NVIDIA API key and enter it from the app's Settings button. The default model is `qwen/qwen3-coder-480b-a35b-instruct`; it can be changed in Settings.

The NVIDIA NIM API endpoint is `https://integrate.api.nvidia.com/v1/chat/completions` and supports OpenAI-compatible chat completion requests. See the NVIDIA API reference for currently available models.

## Local development

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

## APK from GitHub Actions

Push to `main` or run the **Build Android APK** workflow manually. The workflow runs Flutter analysis/tests, builds `app-release.apk`, and uploads it under the artifact name `ai-agent-release-apk`.

For a production release, replace the debug signing configuration in `android/app/build.gradle` with a real Android signing setup and keep keystore credentials in GitHub Actions secrets.

## Security note

The app stores the NVIDIA API key in local preferences to make setup simple. For a public production app, prefer a backend proxy or another architecture that does not embed a long-lived provider credential on client devices.
