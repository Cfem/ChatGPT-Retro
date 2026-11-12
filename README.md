# ChatGPT Retro

A lightweight ChatGPT client designed for legacy iOS devices (iOS 8+).

> **Developer Note:** This project was developed without prior coding knowledge, built entirely with the assistance of Artificial Intelligence (AI pair-programming). It was primarily built and tested on an iPad tablet; iPhone compatibility is implemented but has not been extensively tested.
> Human Sentence: Using AI to use AI, what the world has become.

---

## Features

- **Up-to-Date Model Support** (with live model fetching)
- **iOS 8+ Compatibility** (including 32-bit armv7 architecture)
- **Lightweight Native UI** (~1.1 MB app size, built with pure UIKit and Objective-C)
- **Custom System Instructions & Memory**
- **Reasoning Effort & Model Parameter Controls** (Temperature, Web Search, Code Interpreter)
- **Token & Cost Optimizations** (Prompt Caching, Assistant Response Truncation, History Turn Limiting)
- **Dual Authentication Modes** (OpenAI API Key & QR-assisted Sign-in)

---

## Authentication & Setup

You can use the application through one of the two supported authentication methods:

### Method 1: OpenAI API Key (Recommended)

Direct and stable connection using your personal OpenAI API key.

1. Go to [platform.openai.com](https://platform.openai.com) and create or log in to your account.
2. Navigate to **Settings > Billing** and add credits to your balance (a minimum payment of $5 is typically sufficient for extended usage; note that ChatGPT Plus subscriptions do not cover API credits).
3. Under the **API Keys** section, click `Create new secret key` and copy your key starting with `sk-...`.
4. Open the app on your device, navigate to **Settings > Account & Login Settings**, and enter your API key.

---

### Method 2: QR Code Login via Modern Device (Experimental / SIWC)

> **Notice:** This method is implemented but has not been thoroughly tested across different device environments.

**Why is this required?**
Legacy Mobile Safari on iOS 8 does not support modern web standards, modern TLS handshakes, or Cloudflare verification challenges, making it impossible to directly load OpenAI's modern login page on the device itself.

**How it works:**
1. Selecting **Continue with ChatGPT** initializes a local loopback socket (Port 8787) on the device and generates a PKCE-compliant OAuth authorization QR code.
2. Scan the QR code using a secondary modern smartphone (iPhone or Android) with a contemporary camera and browser.
3. Complete the authentication on the smartphone. The resulting redirect callback URL is then transmitted back to the legacy device (or pasted manually) to establish the session.

---

## Installation

- **Direct Web Install (On-Device):** Visit [https://cfem.github.io/ChatGPT-Retro](https://cfem.github.io/ChatGPT-Retro) directly on your legacy Safari browser and tap **Install on iDevice** (Requires a jailbroken device with `AppSync Unified`).
- **Jailbroken Devices (Manual):** If your device has `AppSync Unified` installed, download `ChatGPTRetro.ipa` directly and install it via Filza, iFunBox, or 3uTools.
- **Non-Jailbroken Devices:** Sideload `ChatGPTRetro.ipa` using tools such as Sideloadly or AltStore via PC/Mac with your free Apple ID.

---

## Building from Source

Requirements:
- macOS with [Theos](https://theos.dev) installed
- `iPhoneOS9.3.sdk` (or iOS 8-compatible SDK)

```bash
cd ChatGPTRetro
make clean && make ipa
```

---

## Disclaimer

This project is an independent open-source software and is not affiliated with, endorsed by, or sponsored by OpenAI. OpenAI and ChatGPT are trademarks of OpenAI, Inc.
