import runpod
from openai import OpenAI
import os

# Connect to local llama-server (OpenAI-compatible API on port 3098)
client = OpenAI(
    base_url="http://localhost:3098/v1",
    api_key="dummy"  # llama-server doesn't require a valid API key
)

def handler(job):
    """Process a RunPod serverless job by forwarding to local llama-server."""
    job_input = job.get("input", {})

    # Extract request parameters
    messages = job_input.get("messages", [])
    model = job_input.get("model", "qwen")
    max_tokens = job_input.get("max_tokens", 512)
    temperature = job_input.get("temperature", 0.7)
    stream = job_input.get("stream", False)

    try:
        # Forward request to local llama-server
        response = client.chat.completions.create(
            model=model,
            messages=messages,
            max_tokens=max_tokens,
            temperature=temperature,
            stream=stream
        )

        if stream:
            return {"error": "Streaming not supported in serverless mode"}
        
        # Return response in OpenAI-compatible format
        return {
            "id": response.id,
            "object": "chat.completion",
            "created": response.created,
            "model": model,
            "choices": [{
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": response.choices[0].message.content
                },
                "finish_reason": response.choices[0].finish_reason
            }],
            "usage": {
                "prompt_tokens": response.usage.prompt_tokens,
                "completion_tokens": response.usage.completion_tokens,
                "total_tokens": response.usage.total_tokens
            }
        }
    except Exception as e:
        return {"error": str(e)}

if __name__ == "__main__":
    runpod.serverless.start({"handler": handler})
