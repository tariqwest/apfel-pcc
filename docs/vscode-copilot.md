# VSCode Copilot BYOK with apfel-plus

VSCode Copilot can use apfel-plus as a **custom chat model** via its [BYOK custom-endpoint support](https://code.visualstudio.com/docs/copilot/customization/language-models#_add-a-custom-endpoint-model). apfel-plus's `/v1/chat/completions` is OpenAI-compatible (streaming SSE with a leading `role` delta and a terminating `data: [DONE]`), so chat works.

## Start the server

```bash
apfel-plus --serve
```

## Copilot configuration

Add this to your VSCode settings (`customendpoint` BYOK provider, chat-completions):

```json
[
  {
    "name": "Apfel",
    "vendor": "customendpoint",
    "apiType": "chat-completions",
    "models": [
      {
        "id": "apple-foundationmodel",
        "name": "Apple Foundation Model",
        "url": "http://127.0.0.1:11434/v1/chat/completions",
        "toolCalling": false,
        "vision": false,
        "maxInputTokens": 4096,
        "maxOutputTokens": 4096
      }
    ]
  }
]
```

The `4096` token limits match the macOS 26 on-device window; on macOS 27 the window is 8192 - `apfel --model-info` prints the live value.

Select **Apple Foundation Model** in the Copilot Chat model picker. Chat requests are served on-device.

## Diagnosing problems

Run the server with debug logging to see every request and response apfel-plus receives (added in 1.5.0):

```bash
APFEL_DEBUG=1 apfel-plus --serve
```

Equivalently, pass the `--debug` flag. This prints the raw request body and the response, which is the fastest way to see what a client is actually sending.

## Known limitation: inline / edit completions are not supported

Copilot's **inline code completion** (and edit predictions) is a fill-in-the-middle (FIM) flow, not a chat flow. The Apple on-device Foundation model has no FIM capability, and apfel-plus returns an honest `501` for the legacy completions endpoint. If you configure apfel-plus as a *completion* model you will see a client-side `AbortError` / `ABORT_ERR` when Copilot gives up on the unsupported request - this is expected, not an apfel-plus bug.

Use apfel-plus as a **chat** model only. (The same applies to other editors - e.g. Zed's chat works, but its legacy `edit_predictions` FIM endpoint cannot.)
