# Local model endpoints

Under Models & API keys, select Local endpoint separately in Speech to text and Text cleanup.

For speech recognition, open Speech-to-text model. Paste and save the complete OpenAI-compatible transcription URL, such as `http://localhost:8080/v1/audio/transcriptions`, and the model ID loaded on that server.

For text cleanup, open Model settings. Paste and save the complete chat completion URL, such as `http://localhost:1234/v1/chat/completions`. Open Model to paste and save the server's model ID. IDs may contain slashes and colons.

Start your model server before dictating. S2T sends WAV audio as a multipart `file` with `model` and `response_format=json` for speech recognition. Text cleanup uses non-streaming chat completions with system and user messages. Custom system prompts, dictionary entries and clipboard placeholders still apply.

The two URLs and model IDs persist independently. Switching back to a cloud provider restores its model settings. Local requests send no API key and never retry through a cloud provider. This option currently supports servers that do not require authentication. A failed cleanup still delivers the original transcript.

For plain HTTP, use localhost, a local hostname or a local IP address. Other hosts should use HTTPS. The app declares local networking support through Apple's NSAllowsLocalNetworking setting: https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking
