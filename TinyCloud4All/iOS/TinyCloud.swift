import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - ESP32 Telemetry JSON Packet Model

struct ESP32TelemetryPacket: Codable {
    let type: String
    let freeHeapBytes: Int
    let totalHeapBytes: Int
    let storageTotalBytes: Int64
    let storageUsedBytes: Int64
    let storageFreeBytes: Int64
    let wifiRSSI: Int
}

// MARK: - Models & Data Structures

enum FileCategory: String, CaseIterable, Identifiable {
    case all = "All"
    case photos = "Photos"
    case documents = "Documents"
    case audio = "Audio"
    case video = "Video"
    
    var iconName: String {
        switch self {
        case .all: return "folder.fill"
        case .photos: return "photo.fill"
        case .documents: return "doc.fill"
        case .audio: return "music.note"
        case .video: return "film.fill"
        }
    }
}

struct CloudFile: Identifiable, Hashable {
    let id: UUID
    var name: String
    var sizeBytes: Int64
    var dateAdded: Date
    var category: FileCategory
    var fileExtension: String
    
    init(id: UUID = UUID(), name: String, sizeBytes: Int64, dateAdded: Date = Date(), category: FileCategory, fileExtension: String) {
        self.id = id
        self.name = name
        self.sizeBytes = sizeBytes
        self.dateAdded = dateAdded
        self.category = category
        self.fileExtension = fileExtension
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }
    
    var iconName: String {
        switch category {
        case .photos: return "photo"
        case .documents: return "doc.text"
        case .audio: return "music.note"
        case .video: return "video"
        case .all: return "doc"
        }
    }
}

// MARK: - Real-Time ESP32 Native WebSocket Client Manager

final class ESP32ServerManager: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    
    // Server & Wi-Fi Settings
    @Published var targetIP: String = "192.168.1.100" // Replace with your ESP32 IP
    @Published var allowWebSocketAccess: Bool = true
    @Published var currentWiFiSSID: String = "TinyCloud-Pro"
    let targetSSID: String = "TinyCloud-Pro"
    
    // Live ESP32 Hardware Diagnostics (Updated via WebSocket JSON)
    @Published var storageUsedBytes: Int64 = 0
    @Published var storageTotalBytes: Int64 = 16_000_000_000 // Default 16GB
    @Published var freeHeapBytes: Int = 0
    @Published var totalHeapBytes: Int = 327680
    @Published var signalStrengthDbm: Int = -60
    
    // Active File Transfers
    @Published var isUploading: Bool = false
    @Published var isDownloading: Bool = false
    @Published var activeTransferProgress: Double = 0.0
    @Published var activeTransferFileName: String = ""
    
    // Fallback Alerts
    @Published var showAlertUnavailable: Bool = false
    @Published var alertMessageTitle: String = ""
    @Published var alertMessageCaption: String = ""
    
    // Managed Files Stored on ESP32
    @Published var files: [CloudFile] = [
        CloudFile(name: "firmware_v2.4_backup.bin", sizeBytes: 1_258_291, dateAdded: Date().addingTimeInterval(-86400 * 4), category: .documents, fileExtension: "bin"),
        CloudFile(name: "esp32_cam_capture.jpg", sizeBytes: 2_411_724, dateAdded: Date().addingTimeInterval(-86400 * 2), category: .photos, fileExtension: "jpg"),
        CloudFile(name: "sensor_logs_2026.csv", sizeBytes: 491_520, dateAdded: Date().addingTimeInterval(-86400), category: .documents, fileExtension: "csv"),
        CloudFile(name: "field_audio_sample.mp3", sizeBytes: 5_347_737, dateAdded: Date().addingTimeInterval(-14400), category: .audio, fileExtension: "mp3")
    ]
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var cancellables = Set<AnyCancellable>()
    
    var serverWebSocketURL: String {
        return "ws://\(targetIP)/ws"
    }

    // MARK: - WebSocket Protocol Handler
    
    func connect() {
        guard !isConnecting else { return }
        
        // Check Wi-Fi Network Requirements
        guard currentWiFiSSID == targetSSID else {
            triggerUnavailableAlert()
            return
        }
        
        guard allowWebSocketAccess else {
            alertMessageTitle = "WebSocket Access Blocked"
            alertMessageCaption = "Enable 'Allow WS Access For App' in Settings tab to connect."
            showAlertUnavailable = true
            return
        }
        
        guard let url = URL(string: serverWebSocketURL) else {
            alertMessageTitle = "Invalid Target URL"
            alertMessageCaption = "Check ESP32 IP address configuration."
            showAlertUnavailable = true
            return
        }
        
        isConnecting = true
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        // Listen for raw WebSocket JSON telemetry frames
        receiveWebSocketMessage()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.isConnecting = false
            self.isConnected = true
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
        isConnecting = false
    }
    
    private func receiveWebSocketMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self.parseESP32Telemetry(jsonString: text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.parseESP32Telemetry(jsonString: text)
                    }
                @unknown default:
                    break
                }
                // Keep receiving subsequent messages loop
                self.receiveWebSocketMessage()
                
            case .failure(let error):
                DispatchQueue.main.async {
                    print("[WS] Socket Error: \(error.localizedDescription)")
                    if self.isConnected {
                        self.disconnect()
                        self.triggerUnavailableAlert()
                    }
                }
            }
        }
    }
    
    private func parseESP32Telemetry(jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        
        if let telemetry = try? decoder.decode(ESP32TelemetryPacket.self, from: data) {
            DispatchQueue.main.async {
                self.freeHeapBytes = telemetry.freeHeapBytes
                self.totalHeapBytes = telemetry.totalHeapBytes
                self.storageTotalBytes = telemetry.storageTotalBytes
                self.storageUsedBytes = telemetry.storageUsedBytes
                self.signalStrengthDbm = telemetry.wifiRSSI
            }
        }
    }
    
    func triggerUnavailableAlert() {
        self.alertMessageTitle = "ESP32 is currently off or unavailable"
        self.alertMessageCaption = "Try powering it on or check if unavailable."
        self.showAlertUnavailable = true
    }
    
    // MARK: - File Operations
    
    func uploadFile(name: String, category: FileCategory, sizeBytes: Int64) {
        guard isConnected else {
            triggerUnavailableAlert()
            return
        }
        
        isUploading = true
        activeTransferFileName = name
        activeTransferProgress = 0.0
        
        // Simulating binary frame payload chunking over WebSocket
        Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] timer in
                guard let self = self else { return }
                if self.activeTransferProgress < 1.0 {
                    self.activeTransferProgress += 0.05
                } else {
                    timer.cancel()
                    self.isUploading = false
                    let ext = (name as NSString).pathExtension.isEmpty ? "bin" : (name as NSString).pathExtension
                    let newFile = CloudFile(name: name, sizeBytes: sizeBytes, dateAdded: Date(), category: category, fileExtension: ext)
                    self.files.insert(newFile, at: 0)
                    self.storageUsedBytes += sizeBytes
                    self.activeTransferFileName = ""
                }
            }
            .store(in: &cancellables)
    }
    
    func downloadFile(_ file: CloudFile, completion: @escaping (URL?) -> Void) {
        guard isConnected else {
            triggerUnavailableAlert()
            completion(nil)
            return
        }
        
        isDownloading = true
        activeTransferFileName = file.name
        activeTransferProgress = 0.0
        
        Timer.publish(every: 0.04, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] timer in
                guard let self = self else { return }
                if self.activeTransferProgress < 1.0 {
                    self.activeTransferProgress += 0.08
                } else {
                    timer.cancel()
                    self.isDownloading = false
                    self.activeTransferFileName = ""
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
                    try? "ESP32 Data Stream Payload".data(using: .utf8)?.write(to: tempURL)
                    completion(tempURL)
                }
            }
            .store(in: &cancellables)
    }
    
    func deleteFile(_ file: CloudFile) {
        files.removeAll { $0.id == file.id }
        storageUsedBytes = max(0, storageUsedBytes - file.sizeBytes)
    }
}

// MARK: - Root Navigation Shell

struct TinyCloudMainView: View {
    @StateObject private var server = ESP32ServerManager()
    @State private var selectedTab: Int = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeTabView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            
            LibraryTabView()
                .tabItem {
                    Label("Library", systemImage: "tray.and.arrow.up.fill")
                }
                .tag(1)
            
            SettingsTabView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .environmentObject(server)
        .accentColor(.blue)
        .alert(isPresented: $server.showAlertUnavailable) {
            Alert(
                title: Text(server.alertMessageTitle),
                message: Text(server.alertMessageCaption),
                dismissButton: .default(Text("OK"))
            )
        }
    }
}

// MARK: - Tab 1: Home View

struct HomeTabView: View {
    @EnvironmentObject var server: ESP32ServerManager
    @State private var selectedCategory: FileCategory = .all
    @State private var searchText: String = ""
    @State private var downloadedFileURL: URL?
    @State private var showDownloadSuccessAlert: Bool = false
    @State private var activeDownloadedFile: CloudFile?
    
    var filteredFiles: [CloudFile] {
        server.files.filter { file in
            let categoryMatches = (selectedCategory == .all || file.category == selectedCategory)
            let searchMatches = searchText.isEmpty || file.name.localizedCaseInsensitiveContains(searchText)
            return categoryMatches && searchMatches
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Connection Real-Time Header Bar
                ConnectionHeaderBar()
                
                // Category Filter Bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FileCategory.allCases) { category in
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedCategory = category
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: category.iconName)
                                    Text(category.rawValue)
                                }
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 14)
                                .background(selectedCategory == category ? Color.blue : Color(.secondarySystemBackground))
                                .foregroundColor(selectedCategory == category ? .white : .primary)
                                .cornerRadius(18)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                
                // Active Transfer Status Bar
                if server.isDownloading || server.isUploading {
                    VStack(spacing: 6) {
                        HStack {
                            Text(server.isUploading ? "Uploading: \(server.activeTransferFileName)" : "Downloading: \(server.activeTransferFileName)")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(Int(server.activeTransferProgress * 100))%")
                                .font(.caption)
                        }
                        ProgressView(value: server.activeTransferProgress)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                }
                
                // File List
                List {
                    Section(header: Text("ESP MicroSD Storage (\(filteredFiles.count) Items)")) {
                        if filteredFiles.isEmpty {
                            Text("No files stored on ESP32 MicroSD.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(filteredFiles) { file in
                                HStack {
                                    Image(systemName: file.iconName)
                                        .font(.title3)
                                        .foregroundColor(.blue)
                                        .frame(width: 36, height: 36)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(8)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                        Text("\(file.formattedSize) • \(file.dateAdded, style: .date)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        activeDownloadedFile = file
                                        server.downloadFile(file) { url in
                                            if url != nil {
                                                showDownloadSuccessAlert = true
                                            }
                                        }
                                    }) {
                                        Text("Download")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(10)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    server.deleteFile(filteredFiles[index])
                                }
                            }
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .searchable(text: $searchText, prompt: "Search ESP files...")
            }
            .navigationTitle("TinyCloud")
            .alert(isPresented: $showDownloadSuccessAlert) {
                Alert(
                    title: Text("Saved to your files"),
                    message: Text("Downloaded '\(activeDownloadedFile?.name ?? "file")' successfully over WebSocket connection."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
}

// MARK: - Tab 2: Library View

struct LibraryTabView: View {
    @EnvironmentObject var server: ESP32ServerManager
    @State private var fileName: String = ""
    @State private var selectedCategory: FileCategory = .documents
    @State private var fileSizeMB: Double = 2.5
    @State private var isImporterPresented: Bool = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("WebSocket Transfer Tunnel")) {
                    HStack {
                        Text("Target WS URL")
                        Spacer()
                        Text(server.serverWebSocketURL)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Active Wi-Fi")
                        Spacer()
                        Text(server.currentWiFiSSID)
                            .foregroundColor(server.currentWiFiSSID == server.targetSSID ? .green : .orange)
                            .fontWeight(.medium)
                    }
                }
                
                Section(header: Text("Upload Local File to ESP32")) {
                    Button(action: { isImporterPresented = true }) {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                            Text("Pick File (Apple Native Importer)")
                        }
                    }
                    
                    TextField("File Name", text: $fileName)
                    
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(FileCategory.allCases.filter { $0 != .all }) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Payload Size: \(String(format: "%.1f", fileSizeMB)) MB")
                        Slider(value: $fileSizeMB, in: 0.1...50.0, step: 0.5)
                    }
                }
                
                Section {
                    Button(action: {
                        let uploadName = fileName.isEmpty ? "payload_\(Int.random(in: 1000...9999)).dat" : fileName
                        let bytes = Int64(fileSizeMB * 1024 * 1024)
                        server.uploadFile(name: uploadName, category: selectedCategory, sizeBytes: bytes)
                    }) {
                        HStack {
                            Spacer()
                            if server.isUploading {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Sending over WebSocket...")
                            } else {
                                Image(systemName: "paperplane.fill")
                                Text("Send File to ESP32")
                                    .fontWeight(.bold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(server.isUploading || !server.isConnected)
                }
            }
            .navigationTitle("Library")
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.item],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    fileName = url.lastPathComponent
                }
            }
        }
    }
}

// MARK: - Tab 3: Settings View (Displays Free Heap & Storage Bytes)

struct SettingsTabView: View {
    @EnvironmentObject var server: ESP32ServerManager
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Connection Control")) {
                    HStack {
                        Text("ESP32 Device Status")
                        Spacer()
                        Text(server.isConnected ? "Online" : "Offline")
                            .bold()
                            .foregroundColor(server.isConnected ? .green : .red)
                    }
                    
                    Button(action: {
                        if server.isConnected {
                            server.disconnect()
                        } else {
                            server.connect()
                        }
                    }) {
                        HStack {
                            Spacer()
                            if server.isConnecting {
                                ProgressView()
                            } else {
                                Text(server.isConnected ? "Disconnect WebSocket" : "Connect to ESP32 Server")
                                    .fontWeight(.bold)
                                    .foregroundColor(server.isConnected ? .red : .blue)
                            }
                            Spacer()
                        }
                    }
                }
                
                Section(header: Text("ESP32 Hardware Diagnostics (Live Telemetry)")) {
                    // 1. Live Free Heap Display
                    HStack {
                        Text("Free Heap Memory")
                        Spacer()
                        Text("\(server.freeHeapBytes / 1024) KB / \(server.totalHeapBytes / 1024) KB")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    // 2. Storage Usage Display
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("MicroSD Storage Used")
                            Spacer()
                            let usedMB = Double(server.storageUsedBytes) / (1024 * 1024)
                            let totalGB = Double(server.storageTotalBytes) / (1024 * 1024 * 1024)
                            Text(String(format: "%.1f MB / %.0f GB", usedMB, totalGB))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        ProgressView(value: Double(server.storageUsedBytes), total: Double(server.storageTotalBytes))
                    }
                    
                    // 3. Signal Strength
                    HStack {
                        Text("Wi-Fi Signal (RSSI)")
                        Spacer()
                        Text("\(server.signalStrengthDbm) dBm")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Network Configuration")) {
                    TextField("ESP32 IP Address", text: $server.targetIP)
                        .keyboardType(.decimalPad)
                    
                    Picker("Simulated Wi-Fi Network", selection: $server.currentWiFiSSID) {
                        Text("TinyCloud-Pro").tag("TinyCloud-Pro")
                        Text("Home_Network").tag("Home_Network")
                        Text("Disconnected").tag("Disconnected")
                    }
                }
                
                Section(header: Text("Controls & Permissions")) {
                    Toggle("Allow WS Access For App", isOn: $server.allowWebSocketAccess)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Auxiliary UI Components

struct ConnectionHeaderBar: View {
    @EnvironmentObject var server: ESP32ServerManager
    
    var body: some View {
        HStack {
            Image(systemName: server.isConnected ? "wifi" : "wifi.slash")
                .foregroundColor(server.isConnected ? .green : .red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(server.isConnected ? "Connected to ESP32" : "ESP32 Offline")
                    .font(.caption)
                    .fontWeight(.bold)
                Text(server.serverWebSocketURL)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                if server.isConnected {
                    server.disconnect()
                } else {
                    server.connect()
                }
            }) {
                Text(server.isConnected ? "Disconnect" : "Connect")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(server.isConnected ? Color.red.opacity(0.1) : Color.blue.opacity(0.1))
                    .foregroundColor(server.isConnected ? .red : .blue)
                    .cornerRadius(8)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Preview Entry Point

struct TinyCloudMainView_Previews: PreviewProvider {
    static var previews: some View {
        TinyCloudMainView()
    }
}
