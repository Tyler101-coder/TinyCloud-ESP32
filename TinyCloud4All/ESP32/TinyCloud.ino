#include <WiFi.h>
#include <AsyncTCP.h>
#include <ESPAsyncWebServer.h>
#include <ArduinoJson.h>
#include "FS.h"
#include "SPIFFS.h" // Or #include "SD.h" if using an external MicroSD Card Module

// Network Configuration
const char* ssid = "TinyCloud-Pro";
const char* password = "your_wifi_password";

// WebServer and WebSocket instances on Port 80
AsyncWebServer server(80);
AsyncWebSocket ws("/ws");

// Send Telemetry Broadcast Timer
unsigned long lastTelemetrySend = 0;
const unsigned long TELEMETRY_INTERVAL = 2000; // Broadcast stats every 2 seconds

// Function to construct and broadcast telemetry payload
void broadcastSystemTelemetry() {
    if (ws.count() == 0) return; // Skip if no iOS/iPadOS clients connected

    StaticJsonDocument<256> doc;

    // 1. Free Heap Data
    size_t freeHeapBytes = ESP.getFreeHeap();
    size_t totalHeapBytes = ESP.getHeapSize();

    // 2. Storage System Data (SPIFFS / SD)
    size_t storageTotalBytes = SPIFFS.totalBytes();
    size_t storageUsedBytes = SPIFFS.usedBytes();
    size_t storageFreeBytes = storageTotalBytes - storageUsedBytes;

    // 3. Populate JSON Document
    doc["type"] = "telemetry";
    doc["freeHeapBytes"] = freeHeapBytes;
    doc["totalHeapBytes"] = totalHeapBytes;
    doc["storageTotalBytes"] = storageTotalBytes;
    doc["storageUsedBytes"] = storageUsedBytes;
    doc["storageFreeBytes"] = storageFreeBytes;
    doc["wifiRSSI"] = WiFi.RSSI();

    // Serialize JSON to String and Send over WebSocket
    String responseJson;
    serializeJson(doc, responseJson);
    ws.textAll(responseJson);
    
    Serial.printf("[WS] Telemetry Broadcast: Free Heap: %d KB | Storage Used: %d KB\n", 
                  freeHeapBytes / 1024, storageUsedBytes / 1024);
}

// Handle incoming WebSocket events
void onEvent(AsyncWebSocket *server, AsyncWebSocketClient *client, AwsEventType type,
             void *arg, uint8_t *data, size_t len) {
    switch (type) {
        case WS_EVT_CONNECT:
            Serial.printf("[WS] Client #%uint connected from %s\n", client->id(), client->remoteIP().toString().c_str());
            // Instantly send system status upon initial connection
            broadcastSystemTelemetry();
            break;
            
        case WS_EVT_DISCONNECT:
            Serial.printf("[WS] Client #%uint disconnected\n", client->id());
            break;
            
        case WS_EVT_DATA:
            // Handle incoming binary or text file data here if needed
            break;
            
        case WS_EVT_PONG:
        case WS_EVT_ERROR:
            break;
    }
}

void setup() {
    Serial.begin(115200);

    // Initialize File Storage System (SPIFFS or SD)
    if (!SPIFFS.begin(true)) {
        Serial.println("[STORAGE] SPIFFS Mount Failed!");
        return;
    }
    Serial.println("[STORAGE] SPIFFS Mounted Successfully.");

    // Connect to Local Wi-Fi
    WiFi.begin(ssid, password);
    Serial.print("[WiFi] Connecting to ");
    Serial.print(ssid);
    while (WiFi.status() != WL_CONNECTED) {
        delay(500);
        Serial.print(".");
    }
    Serial.println("\n[WiFi] Connected!");
    Serial.print("[WiFi] ESP32 IP Address: ");
    Serial.println(WiFi.localIP());

    // Attach WebSocket Event Handler and WebServer Endpoint
    ws.onEvent(onEvent);
    server.addHandler(&ws);
    server.begin();
    
    Serial.println("[SERVER] WebSocket Server Started at ws://" + WiFi.localIP().toString() + "/ws");
}

void loop() {
    // Clean up inactive WebSocket connections
    ws.cleanupClients();

    // Periodically broadcast telemetry stats (Heap + Storage)
    if (millis() - lastTelemetrySend >= TELEMETRY_INTERVAL) {
        lastTelemetrySend = millis();
        broadcastSystemTelemetry();
    }
}
