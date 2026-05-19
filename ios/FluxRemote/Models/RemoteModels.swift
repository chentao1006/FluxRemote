import Foundation

// MARK: - System Stats Models

struct RemoteStatsResponse: Codable {
    let success: Bool
    let data: RemoteSystemStats
}

struct RemoteSystemStats: Codable {
    let hostname: String
    let osVersion: String
    let uptime: String
    let cpu: RemoteCPU?
    let memory: RemoteMemory
    let disk: RemoteDisk
    let loadAvg: String
    let arch: String
    let cpuModel: String?
    let kernel: String?
    let swap: String?
    let memPressure: String?
    let battery: String?
    let netBytes: RemoteNetBytes?
}

struct RemoteNetBytes: Codable {
    let `in`: Int64
    let out: Int64
}

struct RemoteCPU: Codable {
    let user: Double
    let sys: Double
    let idle: Double
}

struct RemoteMemory: Codable {
    let usedMB: Int
    let totalMB: Int
    let freeMB: Int
}

struct RemoteDisk: Codable {
    let percent: String
    let total: String
    let used: String
}

// MARK: - Docker Models

struct DockerResponse: Codable {
    let success: Bool
    let data: [DockerContainer]
}

struct DockerContainer: Codable, Identifiable {
    let id: String
    let names: [String]
    let image: String
    let state: String
    let status: String
    let ports: String
    let command: String?
    let createdAt: String?
    
    var name: String {
        names.first?.replacingOccurrences(of: "/", with: "") ?? "unknown"
    }
    
    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case names = "Names"
        case image = "Image"
        case state = "State"
        case status = "Status"
        case ports = "Ports"
        case command = "Command"
        case createdAt = "CreatedAt"
    }
    
    init(id: String, names: [String], image: String, state: String, status: String, ports: String) {
        self.id = id
        self.names = names
        self.image = image
        self.state = state
        self.status = status
        self.ports = ports
        self.command = nil
        self.createdAt = nil
    }
    
    init(id: String, names: [String], image: String, state: String, status: String, ports: String, command: String?, createdAt: String?) {
        self.id = id
        self.names = names
        self.image = image
        self.state = state
        self.status = status
        self.ports = ports
        self.command = command
        self.createdAt = createdAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Handle ID or id
        if let idVal = try? container.decode(String.self, forKey: .id) {
            self.id = idVal
        } else {
            let altContainer = try decoder.container(keyedBy: DynamicCodingKeys.self)
            self.id = (try? altContainer.decode(String.self, forKey: DynamicCodingKeys(stringValue: "id")!)) ?? "unknown"
        }
        
        // Handle Names as [String] or String
        if let namesArray = try? container.decode([String].self, forKey: .names) {
            self.names = namesArray
        } else if let namesString = try? container.decode(String.self, forKey: .names) {
            self.names = [namesString]
        } else {
            self.names = []
        }
        
        // Handle others with fallbacks to lowercase if needed
        self.image = (try? container.decode(String.self, forKey: .image)) ?? 
                    (try? decoder.container(keyedBy: DynamicCodingKeys.self).decode(String.self, forKey: DynamicCodingKeys(stringValue: "image")!)) ?? ""
        self.state = (try? container.decode(String.self, forKey: .state)) ?? 
                    (try? decoder.container(keyedBy: DynamicCodingKeys.self).decode(String.self, forKey: DynamicCodingKeys(stringValue: "state")!)) ?? "unknown"
        self.status = (try? container.decode(String.self, forKey: .status)) ?? 
                    (try? decoder.container(keyedBy: DynamicCodingKeys.self).decode(String.self, forKey: DynamicCodingKeys(stringValue: "status")!)) ?? "unknown"
        self.ports = (try? container.decode(String.self, forKey: .ports)) ?? 
                    (try? decoder.container(keyedBy: DynamicCodingKeys.self).decode(String.self, forKey: DynamicCodingKeys(stringValue: "ports")!)) ?? ""
        self.command = (try? container.decode(String.self, forKey: .command)) ?? 
                    (try? decoder.container(keyedBy: DynamicCodingKeys.self).decode(String.self, forKey: DynamicCodingKeys(stringValue: "command")!))
        self.createdAt = (try? container.decode(String.self, forKey: .createdAt)) ?? 
                    (try? decoder.container(keyedBy: DynamicCodingKeys.self).decode(String.self, forKey: DynamicCodingKeys(stringValue: "createdAt")!))
    }
}

private struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int?
    init?(intValue: Int) { return nil }
}

struct DockerImage: Codable, Identifiable {
    let id: String
    let repository: String
    let tag: String
    let size: String
    let created: String
    let inUse: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case repository = "Repository"
        case tag = "Tag"
        case size = "Size"
        case created = "CreatedAt"
        case inUse = "InUse"
    }
}

struct DockerImageResponse: Codable {
    let success: Bool
    let data: [DockerImage]
}

// MARK: - Nginx Models

struct NginxResponse: Codable {
    let success: Bool
    let running: Bool?
    let pids: [String]?
    let binPath: String?
    let data: [NginxSite]?
    let error: String?
}

struct NginxSite: Codable, Identifiable {
    let name: String
    let port: String
    let serverName: String
    let status: String
    
    var id: String { name }
}

// MARK: - Process Models

struct ProcessResponse: Codable {
    let success: Bool
    let data: [RemoteProcess]
}

struct RemoteProcess: Codable, Identifiable {
    let pid: String
    let user: String
    let cpu: String
    let mem: String
    let command: String
    
    var id: String { pid }
}

// MARK: - Port Models

struct PortEntry: Codable, Identifiable, Hashable {
    let protocolName: String
    let port: Int
    let address: String
    let endpoint: String
    let endpoints: [String]?
    let connectionCount: Int?
    let state: String

    var id: String { "\(protocolName)-\(port)-\(endpoint)-\(state)" }

    enum CodingKeys: String, CodingKey {
        case protocolName = "protocol"
        case port
        case address
        case endpoint
        case endpoints
        case connectionCount
        case state
    }

    init(protocolName: String, port: Int, address: String, endpoint: String, endpoints: [String]? = nil, connectionCount: Int? = nil, state: String = "") {
        self.protocolName = protocolName
        self.port = port
        self.address = address
        self.endpoint = endpoint
        self.endpoints = endpoints
        self.connectionCount = connectionCount
        self.state = state
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.protocolName = (try? container.decode(String.self, forKey: .protocolName)) ?? ""
        self.port = (try? container.decode(Int.self, forKey: .port)) ?? 0
        self.address = (try? container.decode(String.self, forKey: .address)) ?? ""
        self.endpoint = (try? container.decode(String.self, forKey: .endpoint)) ?? ""
        self.endpoints = try? container.decode([String].self, forKey: .endpoints)
        self.connectionCount = try? container.decode(Int.self, forKey: .connectionCount)
        self.state = (try? container.decode(String.self, forKey: .state)) ?? ""
    }
}

struct PortProcessGroup: Codable, Identifiable {
    let pid: String
    let command: String
    let user: String
    let cpu: String
    let mem: String
    let ppid: String
    let start: String
    let fullCommand: String
    let ports: [PortEntry]

    var id: String { pid }

    enum CodingKeys: String, CodingKey {
        case pid, command, user, cpu, mem, ppid, start, fullCommand, ports
    }

    init(pid: String, command: String, user: String, cpu: String, mem: String, ppid: String = "", start: String = "", fullCommand: String = "", ports: [PortEntry]) {
        self.pid = pid
        self.command = command
        self.user = user
        self.cpu = cpu
        self.mem = mem
        self.ppid = ppid
        self.start = start
        self.fullCommand = fullCommand
        self.ports = ports
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pid = try container.decode(String.self, forKey: .pid)
        self.command = try container.decode(String.self, forKey: .command)
        self.user = (try? container.decode(String.self, forKey: .user)) ?? ""
        self.cpu = (try? container.decode(String.self, forKey: .cpu)) ?? "0.0"
        self.mem = (try? container.decode(String.self, forKey: .mem)) ?? "0.0"
        self.ppid = (try? container.decode(String.self, forKey: .ppid)) ?? ""
        self.start = (try? container.decode(String.self, forKey: .start)) ?? ""
        self.fullCommand = (try? container.decode(String.self, forKey: .fullCommand)) ?? command
        self.ports = (try? container.decode([PortEntry].self, forKey: .ports)) ?? []
    }
}

struct PortSummary: Codable {
    let processes: Int
    let ports: Int
    let listening: Int

    static let empty = PortSummary(processes: 0, ports: 0, listening: 0)
}

struct PortsResponse: Codable {
    let success: Bool
    let data: [PortProcessGroup]
    let summary: PortSummary
    let error: String?
    let details: String?
}

// MARK: - Log Models

struct LogItem: Codable, Identifiable, Hashable {
    let path: String
    let name: String
    let dir: String
    let category: String
    let size: Int
    let mtime: Int64
    let isCustom: Bool
    
    var id: String { path }
}

struct LogResponse: Codable {
    let success: Bool
    let data: LogData
    let error: String?
    
    enum LogData: Codable {
        case list([LogItem])
        case content(String)
        case error(String)
        
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let list = try? container.decode([LogItem].self) {
                self = .list(list)
            } else if let content = try? container.decode(String.self) {
                self = .content(content)
            } else {
                self = .error("Unknown log data format")
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .list(let list): try container.encode(list)
            case .content(let content): try container.encode(content)
            case .error(let error): try container.encode(error)
            }
        }
    }
}

// MARK: - Config Models

struct ConfigItem: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let category: String
    let size: Int?
    let mtime: Double?
}

struct ConfigResponse: Codable {
    let success: Bool
    let data: [ConfigItem]?
    let content: String?
}

// MARK: - Launch Agent Models

struct LaunchAgentResponse: Codable {
    let success: Bool
    let data: [LaunchAgentItem]
}

struct LaunchAgentItem: Codable, Identifiable {
    let name: String
    let label: String?
    let path: String
    let isLoaded: Bool
    let size: Int64
    let mtime: Int64
    
    var id: String { path }
}

// MARK: - Settings Models

struct ServerSettingsResponse: Codable {
    let success: Bool
    let data: ServerSettings
}

struct ServerSettings: Codable {
    var ai: AIConfig?
    var features: FeatureToggles?
    var version: String?
}

struct AIConfig: Codable {
    var enabled: Bool?
    var url: String?
    var key: String?
    var model: String?
    var usePublicService: Bool?
    var stream: Bool?
}

struct FeatureToggles: Codable {
    var monitor: Bool?
    var processes: Bool?
    var ports: Bool?
    var logs: Bool?
    var configs: Bool?
    var launchagent: Bool?
    var docker: Bool?
    var nginx: Bool?
}

// MARK: - Common Response

struct ActionResponse: Codable {
    let success: Bool
    let error: String?
    let requiresPassword: Bool?
    let data: String?
    let details: String?
}

struct AIResponse: Codable {
    let success: Bool
    let data: String
}

struct GenericLogResponse: Codable {
    let success: Bool
    let logs: String
}

struct ScreenshotResponse: Codable {
    let success: Bool
    let data: String? // Base64 encoded image
    let error: String?
}
