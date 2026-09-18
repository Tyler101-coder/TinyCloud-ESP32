# TinyCloud

**TinyCloud** is a free, ESP-powered local cloud storage solution tailored for the Apple ecosystem. It allows you to store, manage, and browse your files and photos directly on an ESP32 microcontroller with attached MicroSD storage using WebSockets.

---

## 📱 Features & Supported Platforms

* **Universal Apple Ecosystem Support:** Designed for iOS, iPadOS, macOS, visionOS, CarPlay, and watchOS.
* **Local WebSocket Server:** Fast, direct file transfers to your ESP32 MicroSD card without relying on third-party cloud servers.
* **Automatic Fallback Handling:** Prompts clear connection alerts if the micro-server is disconnected or powered off.
* **Categorized File Management:** Automatically sorts uploaded files for quick browsing.

---

## 🛠️ Connection & Setup

To transfer files to your ESP32 MicroSD card via WebSocket, complete the following setup steps:

1. **Connect to Wi-Fi:** Ensure your Apple device is connected to the same local network (`TinyCloud-Pro`).
2. **Grant Permissions:** Allow WebSocket access when prompted by the app.
3. **Server Address:** The app connects to the default ESP-Server endpoint at `https://192.000.000.9.1.0` once connected to the network.

---

## 📥 Installing & Downloading Files

To save files from the ESP32 storage to your local device:

1. Select the file you want to download.
2. Tap **Download**.
3. Grant permission to access Apple **Files** when requested.
4. The file will save directly to your local system storage.

---

## 🗂️ App Navigation & Tabs

* **Home:** Browse all files stored on your ESP32, neatly categorized by type.
* **Library:** Pick and send new files or photos to the ESP32 WebSocket server.
* **Settings:** Manage connection preferences, app controls, and system permissions.

---

## ⚠️ Error Handling

If the ESP32 server becomes unreachable, the app will display a fallback alert:

* **Title:** `ESP32 is currently off or unavailable`
* **Message:** `Try powering it on or check if unavailable.`
