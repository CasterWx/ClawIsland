import Foundation

class BridgeServer {
    private let socketPath = "/tmp/clawisland.sock"
    private var listeningSocket: Int32 = -1
    private let state: SessionState
    
    init(state: SessionState) {
        self.state = state
    }
    
    func start() {
        DispatchQueue.global(qos: .background).async {
            self.runServer()
        }
    }
    
    private func runServer() {
        unlink(socketPath)
        
        listeningSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listeningSocket != -1 else {
            print("Failed to create socket")
            return
        }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathLength = socketPath.utf8CString.count
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            socketPath.withCString {
                strncpy(ptr, $0, pathLength)
            }
        }
        
        let addrLen = socklen_t(MemoryLayout.size(ofValue: addr))
        
        guard withUnsafePointer(to: &addr, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listeningSocket, $0, addrLen)
            }
        }) != -1 else {
            print("Failed to bind socket")
            return
        }
        
        guard listen(listeningSocket, 5) != -1 else { return }
        
        print("Listening on \(socketPath)...")
        
        while true {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout.size(ofValue: clientAddr))
            
            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(listeningSocket, $0, &clientAddrLen)
                }
            }
            
            if clientSocket != -1 {
                handleConnection(clientSocket: clientSocket)
            }
        }
    }
    
    private func handleConnection(clientSocket: Int32) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fileHandle = FileHandle(fileDescriptor: clientSocket)
            
            // Read once to prevent deadlocking. Python sends the JSON all at once.
            // Using upToCount covers very large JSONs (1MB) safely without blocking for EOF.
            guard let data = try? fileHandle.read(upToCount: 1024 * 1024), !data.isEmpty else {
                fileHandle.closeFile()
                return
            }
            
            let jsonStr = String(data: data, encoding: .utf8) ?? ""
            print("Received JSON: \(jsonStr.prefix(200))...")
            
            let decoder = JSONDecoder()
            do {
                let payload = try decoder.decode(HookPayload.self, from: data)
                DispatchQueue.main.async {
                    self.state.updateState(payload: payload, connection: fileHandle)
                }
            } catch {
                print("Decoding Error: \(error)")
                let errorPayload = HookPayload(
                    hookEventName: "Error",
                    prompt: "Failed to parse: \(error.localizedDescription)\nRaw: \(jsonStr.prefix(100))..."
                )
                DispatchQueue.main.async {
                    self.state.updateState(payload: errorPayload, connection: fileHandle)
                }
            }
        }
    }
}
