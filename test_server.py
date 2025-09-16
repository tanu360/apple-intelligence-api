#!/usr/bin/env python3

import requests
from openai import OpenAI

BASE_URL = "http://127.0.0.1:11435"
API_BASE_URL = f"{BASE_URL}/v1"


def test_status():
    print("\n🔍 Testing server status...")
    try:
        response = requests.get(f"{BASE_URL}/status")
        if response.status_code == 200:
            data = response.json()
            print("✅ Status check passed")
            print(f"   Model available: {data.get('model_available', False)}")
            return data.get("model_available", False)
        else:
            print(f"❌ Status check failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Status check error: {e}")
        return False


def test_models_list():
    print("\n🔍 Testing models list...")
    try:
        client = OpenAI(base_url=API_BASE_URL, api_key="dummy-key")
        models = client.models.list()
        print("✅ Models list retrieved successfully")
        print(f"   Available models count: {len(models.data)}")
        for model in models.data:
            print(f"   - {model.id}")
        return True
    except Exception as e:
        print(f"❌ Models list retrieval error: {e}")
        return False


def test_chat_completion():
    print("\n🔍 Testing multi-turn chat completion...")
    models_to_test = ["apple-fm-base", "apple-fm-deterministic", "apple-fm-creative"]

    for model_name in models_to_test:
        print(f"\n  Testing model: {model_name}")
        try:
            client = OpenAI(base_url=API_BASE_URL, api_key="dummy-key")
            response = client.chat.completions.create(
                model=model_name,
                messages=[
                    {
                        "role": "user",
                        "content": "What are the benefits of on-device AI?",
                    },
                    {
                        "role": "assistant",
                        "content": "On-device AI offers several key benefits including improved privacy, faster response times, reduced reliance on internet connectivity, and better data security since processing happens locally on your device.",
                    },
                    {
                        "role": "user",
                        "content": "Can you elaborate on the privacy benefits?",
                    },
                ],
                max_tokens=200,
            )
            print(f"  ✅ {model_name} call successful")
            print(f"     AI Response: {response.choices[0].message.content}")
        except Exception as e:
            print(f"  ❌ {model_name} call failed: {e}")
            return False

    print("✅ All model tests completed successfully")
    return True


def test_french_conversation():
    print("\n🔍 Testing French conversation...")
    try:
        client = OpenAI(base_url=API_BASE_URL, api_key="dummy-key")
        response = client.chat.completions.create(
            model="apple-fm-base",
            messages=[
                {
                    "role": "user",
                    "content": "Bonjour! Pouvez-vous expliquer ce qu'est Apple Intelligence en français?",
                }
            ],
            max_tokens=200,
        )
        print("✅ French conversation successful")
        print(f"   AI Response: {response.choices[0].message.content}")
        return True
    except Exception as e:
        print(f"❌ French conversation error: {e}")
        return False


def test_streaming_chat():
    print("\n🔍 Testing streaming chat completion...")
    try:
        client = OpenAI(base_url=API_BASE_URL, api_key="dummy-key")
        stream = client.chat.completions.create(
            model="apple-fm-creative",
            messages=[
                {
                    "role": "user",
                    "content": "Tell me a short story about AI helping humans.",
                }
            ],
            max_tokens=150,
            stream=True,
        )
        print("✅ Streaming chat completion started")
        collected_content = ""
        chunk_count = 0

        for chunk in stream:
            if chunk.choices[0].delta.content is not None:
                content = chunk.choices[0].delta.content
                collected_content += content
                chunk_count += 1
                print(f"   Chunk {chunk_count}: '{content}'")

        print(f"✅ Streaming completed with {chunk_count} chunks")
        print(f"   Full response: {collected_content}")
        return True
    except Exception as e:
        print(f"❌ Streaming chat completion failed: {e}")
        return False


def main():
    print("🚀 Starting Apple On-Device OpenAI Compatible Server Tests")
    print("=" * 60)

    model_available = test_status()
    test_models_list()

    if model_available:
        print("\n" + "=" * 60)
        print("🤖 Model available, starting chat tests")
        print("=" * 60)

        test_chat_completion()
        test_french_conversation()

        print("\n" + "=" * 60)
        print("🌊 Testing streaming functionality")
        print("=" * 60)

        test_streaming_chat()

        print("\n" + "=" * 60)
        print("✅ All tests completed!")
        print(f"\n💡 Base URL: {API_BASE_URL}")
        print("   Models: apple-fm-base, apple-fm-deterministic, apple-fm-creative")
    else:
        print("\n⚠️  Model unavailable, skipping chat tests")
        print("Please ensure:")
        print("1. Device supports Apple Intelligence")
        print("2. Apple Intelligence is enabled in Settings")
        print("3. Model download is complete")


if __name__ == "__main__":
    main()
