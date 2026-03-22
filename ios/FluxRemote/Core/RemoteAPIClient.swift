import Foundation
import Observation
import SwiftUI

// MARK: - Language Management

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case chinese = "zh-Hans"
    case english = "en"
    
    var id: String { self.rawValue }
    
    var locale: Locale? {
        switch self {
        case .system: return nil
        case .chinese: return Locale(identifier: "zh-Hans")
        case .english: return Locale(identifier: "en")
        }
    }
    
    var displayNameKey: String {
        switch self {
        case .system: return "common.systemDefault"
        case .chinese: return "简体中文"
        case .english: return "English"
        }
    }
}

@MainActor
@Observable
class AppLanguageManager {
    private let translations: [String: [String: String]] = [
        "appTitle": ["en": "Flux Monitor", "zh-Hans": "浮光面板"],
        
        // Sidebar & Navigation
        "sidebar.monitor": ["en": "Monitor", "zh-Hans": "系统概览"],
        "sidebar.processes": ["en": "Processes", "zh-Hans": "进程管理"],
        "sidebar.logs": ["en": "Logs", "zh-Hans": "日志分析"],
        "sidebar.configs": ["en": "Configs", "zh-Hans": "配置管理"],
        "sidebar.launchagent": ["en": "LaunchAgent", "zh-Hans": "自启服务"],
        "sidebar.docker": ["en": "Docker", "zh-Hans": "Docker"],
        "sidebar.nginx": ["en": "Nginx", "zh-Hans": "Nginx"],
        "sidebar.settings": ["en": "Settings", "zh-Hans": "系统设置"],
        "sidebar.home": ["en": "Home", "zh-Hans": "主页"],
        "sidebar.systemTools": ["en": "System Tools", "zh-Hans": "系统工具"],
        "sidebar.serviceManagement": ["en": "Service Management", "zh-Hans": "服务管理"],
        "sidebar.system": ["en": "System", "zh-Hans": "系统"],
        
        // Common
        "common.systemDefault": ["en": "Auto", "zh-Hans": "跟随系统"],
        "common.loading": ["en": "Loading...", "zh-Hans": "加载中..."],
        "common.none": ["en": "None", "zh-Hans": "无"],
        "common.unknown": ["en": "Unknown", "zh-Hans": "未知"],
        "common.saveSuccess": ["en": "Saved", "zh-Hans": "已保存"],
        "common.all": ["en": "All", "zh-Hans": "全部"],
        "common.add": ["en": "Add", "zh-Hans": "添加"],
        "common.cancel": ["en": "Cancel", "zh-Hans": "取消"],
        "common.refresh": ["en": "Refresh", "zh-Hans": "刷新数据"],
        "common.more": ["en": "More", "zh-Hans": "更多"],
        "common.test": ["en": "Test", "zh-Hans": "测试"],
        "common.error": ["en": "Error", "zh-Hans": "读取失败"],
        "common.failed": ["en": "Failed", "zh-Hans": "执行失败"],
        "common.basicInfo": ["en": "Basic Info", "zh-Hans": "基础信息"],
        "common.resourceUsage": ["en": "Resource Usage", "zh-Hans": "资源占用"],
        "common.category": ["en": "Category", "zh-Hans": "分类"],
        "common.id": ["en": "ID", "zh-Hans": "ID"],
        "common.url": ["en": "URL", "zh-Hans": "地址"],
        "common.pids": ["en": "PIDs", "zh-Hans": "进程 ID"],
        "common.command": ["en": "Command", "zh-Hans": "命令"],
        
        // Monitor
        "monitor.title": ["en": "System Overview", "zh-Hans": "系统概览"],
        "monitor.cpu": ["en": "CPU Usage", "zh-Hans": "CPU 使用率"],
        "monitor.memory": ["en": "Memory Usage", "zh-Hans": "内存使用率"],
        "monitor.network": ["en": "Network Traffic", "zh-Hans": "网络流量"],
        "monitor.hostname": ["en": "Hostname", "zh-Hans": "主机名"],
        "monitor.osVersion": ["en": "OS Version", "zh-Hans": "系统版本"],
        "monitor.uptime": ["en": "Uptime", "zh-Hans": "运行时间"],
        "monitor.arch": ["en": "Architecture", "zh-Hans": "架构"],
        "monitor.diskSpace": ["en": "Disk Space", "zh-Hans": "磁盘空间"],
        "monitor.loadAvg": ["en": "Load Average", "zh-Hans": "负载"],
        "monitor.battery": ["en": "Battery", "zh-Hans": "电池"],
        "monitor.memPressure": ["en": "Memory Pressure", "zh-Hans": "内存压力"],
        "monitor.screenshot": ["en": "Screen Capture", "zh-Hans": "屏幕快照"],
        "monitor.user": ["en": "User", "zh-Hans": "用户"],
        "monitor.sys": ["en": "Sys", "zh-Hans": "系统"],
        "monitor.download": ["en": "Download", "zh-Hans": "下载"],
        "monitor.upload": ["en": "Upload", "zh-Hans": "上传"],
        "monitor.analysisFailed": ["en": "Analysis Failed", "zh-Hans": "分析失败"],
        "monitor.decodeFailed": ["en": "Decode Failed", "zh-Hans": "解码失败"],
        "monitor.accumulated": ["en": "Accumulated", "zh-Hans": "累计交换"],
        
        // Quick Commands
        "monitor.quickCmds.ls": ["en": "Directory", "zh-Hans": "目录"],
        "monitor.quickCmds.df": ["en": "Disk", "zh-Hans": "磁盘"],
        "monitor.quickCmds.memSort": ["en": "Mem Top", "zh-Hans": "内存排行"],
        "monitor.quickCmds.cpuSort": ["en": "CPU Top", "zh-Hans": "CPU 排行"],
        "monitor.quickCmds.ip": ["en": "Local IP", "zh-Hans": "本机 IP"],
        "monitor.quickCmds.ports": ["en": "Ports", "zh-Hans": "监听端口"],
        "monitor.quickCmds.uptime": ["en": "Uptime", "zh-Hans": "运行时间"],
        "monitor.quickCmds.brew": ["en": "Brew", "zh-Hans": "Brew"],
        "monitor.quickCmds.vers": ["en": "Sys Vers", "zh-Hans": "系统版本"],
        "monitor.quickCmds.procCount": ["en": "Processes", "zh-Hans": "进程数"],
        "monitor.quickCmds.space": ["en": "Space", "zh-Hans": "空间详情"],
        "monitor.quickCmds.downloads": ["en": "Downloads", "zh-Hans": "下载历史"],
        "monitor.quickCmds.arch": ["en": "Arch", "zh-Hans": "硬件架构"],
        "monitor.quickCmds.who": ["en": "Who", "zh-Hans": "活跃用户"],
        "monitor.quickCmds.dns": ["en": "DNS", "zh-Hans": "DNS 配置"],
        
        // Processes
        "processes.title": ["en": "Processes", "zh-Hans": "进程"],
        "processes.pid": ["en": "PID", "zh-Hans": "PID"],
        "processes.user": ["en": "User", "zh-Hans": "用户"],
        "processes.cpu": ["en": "CPU", "zh-Hans": "CPU"],
        "processes.mem": ["en": "MEM", "zh-Hans": "内存"],
        "processes.kill": ["en": "Kill Process", "zh-Hans": "结束进程"],
        "processes.details": ["en": "Process Details", "zh-Hans": "进程详细信息"],
        "processes.parentPid": ["en": "Parent PID", "zh-Hans": "父进程"],
        "processes.state": ["en": "State", "zh-Hans": "状态"],
        "processes.startTime": ["en": "Start Time", "zh-Hans": "启动时间"],
        "processes.cpuTime": ["en": "Total CPU Time", "zh-Hans": "运行时长"],
        "processes.fullCommand": ["en": "Full Command", "zh-Hans": "全路径命令"],
        "processes.openFiles": ["en": "Open Files/Connections", "zh-Hans": "打开的文件 (LSOF)"],
        "processes.terminate": ["en": "Terminate (SIGTERM)", "zh-Hans": "停止进程"],
        "processes.forceKill": ["en": "Force Kill (SIGKILL)", "zh-Hans": "强制结束进程"],
        "processes.terminateConfirm": ["en": "Are you sure you want to terminate this process (SIGTERM)?", "zh-Hans": "确定要安全停止进程吗 (SIGTERM)?"],
        "processes.forceKillConfirm": ["en": "Are you sure you want to force kill this process (SIGKILL)?", "zh-Hans": "确定要强制结束进程吗 (SIGKILL)?"],
        "processes.searchPlaceholder": ["en": "Search Name or PID...", "zh-Hans": "搜索名称或 PID..."],
        "processes.sort": ["en": "Sort", "zh-Hans": "排序"],
        "processes.fetchFailed": ["en": "Fetch Failed", "zh-Hans": "读取失败"],
        "processes.noData": ["en": "No Processes", "zh-Hans": "无进程数据"],
        
        // Logs
        "logs.title": ["en": "Log Analysis", "zh-Hans": "日志分析"],
        "logs.searchPlaceholder": ["en": "Search log files...", "zh-Hans": "搜索日志文件..."],
        "logs.addPath": ["en": "Add Log Path", "zh-Hans": "添加日志路径"],
        "logs.pathPlaceholder": ["en": "Path (Absolute Path)", "zh-Hans": "路径 (绝对路径)"],
        "logs.namePlaceholder": ["en": "Display Name (Optional)", "zh-Hans": "显示名称 (可选)"],
        "logs.syncing": ["en": "Syncing logs...", "zh-Hans": "正在同步日志..."],
        "logs.syncFailed": ["en": "Sync Failed", "zh-Hans": "同步失败"],
        "logs.noLogs": ["en": "No log files found", "zh-Hans": "无日志文件"],
        "logs.noLogsDesc": ["en": "Add a log path to start monitoring", "zh-Hans": "添加日志路径以开始监控"],
        "logs.noContent": ["en": "No log content", "zh-Hans": "无日志内容"],
        
        // Configs
        "configs.title": ["en": "Config Management", "zh-Hans": "配置管理"],
        "configs.searchPlaceholder": ["en": "Search configs...", "zh-Hans": "搜索配置..."],
        "configs.addPath": ["en": "Add Config Path", "zh-Hans": "添加配置文件路径"],
        "configs.loading": ["en": "Loading configs...", "zh-Hans": "正在加载配置文件..."],
        "configs.noConfigs": ["en": "No config files found", "zh-Hans": "无配置文件"],
        
        // LaunchAgent
        "launchagent.title": ["en": "LaunchAgent", "zh-Hans": "自启服务"],
        "launchagent.loading": ["en": "Loading launch agents...", "zh-Hans": "正在读取自启服务..."],
        "launchagent.deleteConfirmTitle": ["en": "Confirm Delete?", "zh-Hans": "确认删除？"],
        "launchagent.deleteConfirmMessage": ["en": "Are you sure you want to delete %@? This action cannot be undone.", "zh-Hans": "确定要删除 %@ 吗？此操作不可恢复。"],
        "launchagent.delete": ["en": "Delete", "zh-Hans": "删除"],
        
        // Docker
        "docker.containers": ["en": "Containers", "zh-Hans": "容器"],
        "docker.images": ["en": "Images", "zh-Hans": "镜像"],
        "docker.syncing": ["en": "Syncing Docker data...", "zh-Hans": "正在同步 Docker 数据..."],
        "docker.logs": ["en": "Logs", "zh-Hans": "日志"],
        "docker.containerLogs": ["en": "%@ Logs", "zh-Hans": "%@ 日志"],
        
        // Nginx
        "nginx.runningStatus": ["en": "Running Status", "zh-Hans": "运行状态"],
        "nginx.binPath": ["en": "Path: %@", "zh-Hans": "路径: %@"],
        "nginx.viewErrorLogs": ["en": "View Error Logs", "zh-Hans": "查看错误日志"],
        "nginx.serviceControl": ["en": "Service Control", "zh-Hans": "服务控制"],
        "nginx.siteManagement": ["en": "Site Management", "zh-Hans": "站点管理"],
        "nginx.addSite": ["en": "Add Nginx Site", "zh-Hans": "添加 Nginx 站点"],
        "nginx.filenamePlaceholder": ["en": "Config Filename (e.g. app.conf)", "zh-Hans": "配置文件名 (如 app.conf)"],
        "nginx.errorLogs": ["en": "Nginx Error Logs", "zh-Hans": "Nginx 错误日志"],
        "nginx.noLogData": ["en": "No error log data found", "zh-Hans": "未找到错误日志数据"],
        "nginx.sudoRequired": ["en": "Sudo password required. Please use the web version or wait for password integration.", "zh-Hans": "需要 sudo 密码。请前往网页版操作或等候后续集成密码输入。"],
        
        // Server Control
        "server.status": ["en": "Status", "zh-Hans": "服务状态"],
        "server.controlPanel": ["en": "Control Panel", "zh-Hans": "控制面板"],
        "server.start": ["en": "Start", "zh-Hans": "启动"],
        "server.stop": ["en": "Stop", "zh-Hans": "停止"],
        "server.restart": ["en": "Restart", "zh-Hans": "重启"],
        "server.reload": ["en": "Reload", "zh-Hans": "重载"],
        
        // Settings
        "settings.title": ["en": "Settings", "zh-Hans": "系统设置"],
        "settings.language": ["en": "Language", "zh-Hans": "语言设置"],
        "settings.connection": ["en": "Connection", "zh-Hans": "面板连接"],
        "settings.server": ["en": "Server", "zh-Hans": "服务器"],
        "settings.version": ["en": "Version", "zh-Hans": "版本"],
        "settings.aiConfig": ["en": "AI Service Configuration", "zh-Hans": "AI 服务配置"],
        "settings.featureControl": ["en": "Feature Control", "zh-Hans": "功能模块控制"],
        "settings.account": ["en": "Account", "zh-Hans": "账户"],
        "settings.currentUser": ["en": "Current User", "zh-Hans": "当前用户"],
        "settings.syncData": ["en": "Sync Global Data", "zh-Hans": "同步全局数据"],
        "settings.logout": ["en": "Logout", "zh-Hans": "退出登录"],
        "settings.localSettings": ["en": "Local Settings", "zh-Hans": "本地设置"],
        "settings.iosAppDesc": ["en": "FluxRemote is a native iOS client that strictly follows the functionality and layout of the Web version, providing you with the ultimate monitoring experience.", "zh-Hans": "FluxRemote 是原生 iOS 客户端，严格遵循 Web 版的功能与布局，为您提供极致的监控体验。"],
        "settings.model": ["en": "AI Model", "zh-Hans": "AI 模型"],
        
        // Terminal
        "terminal.title": ["en": "Terminal", "zh-Hans": "终端命令执行"],
        "terminal.placeholder": ["en": "Enter command...", "zh-Hans": "输入命令..."],
        "terminal.output": ["en": "Terminal Output", "zh-Hans": "终端输出"],
        "terminal.waiting": ["en": "Waiting for command...", "zh-Hans": "等待指令..."],
        "terminal.executing": ["en": "Executing", "zh-Hans": "正在执行"],
        "terminal.finished": ["en": "Finished", "zh-Hans": "执行完毕"],
        "terminal.stopped": ["en": "Stopped", "zh-Hans": "操作已停止"],
        
        // Login
        "login.title": ["en": "FLUX", "zh-Hans": "FLUX"],
        "login.subtitle": ["en": "macOS Server Dashboard", "zh-Hans": "macOS 服务器管理面板"],
        "login.username": ["en": "Username", "zh-Hans": "用户名"],
        "login.password": ["en": "Password", "zh-Hans": "密码"],
        "login.submit": ["en": "Login", "zh-Hans": "登录"],
        "login.submitting": ["en": "Logging in...", "zh-Hans": "登录中..."],
        "login.serverURL": ["en": "Server Address (https://...)", "zh-Hans": "服务器地址 (https://...)"],
        "login.accessKey": ["en": "Access Key", "zh-Hans": "访问密钥"],
        "login.loginBtn": ["en": "Login Now", "zh-Hans": "立即登录"],
        "login.safeConnection": ["en": "FluxRemote Secure Connection", "zh-Hans": "FluxRemote 安全连接"],
        
        // Misc
        "MEM": ["en": "MEM", "zh-Hans": "内存"],
        "PID": ["en": "PID", "zh-Hans": "进程 ID"],
    ]
    
    var selectedLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: "app_language")
        }
    }
    
    init() {
        let saved = UserDefaults.standard.string(forKey: "app_language") ?? "system"
        self.selectedLanguage = AppLanguage(rawValue: saved) ?? .system
    }
    
    func t(_ key: String) -> String {
        let lang: String
        if selectedLanguage == .system {
            let pref = Locale.preferredLanguages.first ?? "zh-Hans"
            lang = pref.hasPrefix("en") ? "en" : "zh-Hans"
        } else {
            lang = selectedLanguage.rawValue
        }
        
        return translations[key]?[lang] ?? key
    }
}

// MARK: - Remote API Client

@MainActor
@Observable
class RemoteAPIClient {
    var baseURL: URL?
    var isAuthenticated: Bool = false
    var currentUser: String?
    var isLoading: Bool = false
    var errorMessage: String?
    var features: FeatureToggles = FeatureToggles()
    
    let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        self.session = URLSession(configuration: config)
        
        // Load session from defaults
        if let savedURL = UserDefaults.standard.string(forKey: "flux_remote_url") {
            var urlStr = savedURL
            if !urlStr.hasSuffix("/") { urlStr += "/" }
            self.baseURL = URL(string: urlStr)
        }
        self.isAuthenticated = UserDefaults.standard.bool(forKey: "flux_remote_auth")
        self.currentUser = UserDefaults.standard.string(forKey: "flux_remote_user")
    }
    
    func login(urlString: String, credentials: [String: String]) async {
        isLoading = true
        errorMessage = nil
        
        var cleanURL = urlString
        if cleanURL.hasSuffix("/") { cleanURL.removeLast() }
        
        var finalURLString = cleanURL
        if !finalURLString.hasSuffix("/") { finalURLString += "/" }
        
        guard let url = URL(string: finalURLString) else {
            errorMessage = "Invalid URL format"
            isLoading = false
            return
        }
        
        self.baseURL = url
        
        do {
            let body = try JSONEncoder().encode(credentials)
            var request = URLRequest(url: url.appendingPathComponent("/api/auth/login"))
            request.httpMethod = "POST"
            request.timeoutInterval = 15.0
            
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            
            let (_, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                errorMessage = "Authentication failed"
                isLoading = false
                return
            }
            
            // Success
            isAuthenticated = true
            currentUser = credentials["username"]
            
            UserDefaults.standard.set(cleanURL, forKey: "flux_remote_url")
            UserDefaults.standard.set(true, forKey: "flux_remote_auth")
            UserDefaults.standard.set(currentUser, forKey: "flux_remote_user")
            
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
    
    func logout() {
        isAuthenticated = false
        currentUser = nil
        UserDefaults.standard.set(false, forKey: "flux_remote_auth")
        UserDefaults.standard.removeObject(forKey: "flux_remote_user")
    }
    
    func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        guard let baseURL = baseURL, let url = URL(string: path.hasPrefix("/") ? String(path.dropFirst()) : path, relativeTo: baseURL) else {
            throw NSError(domain: "APIClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "No Base URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("FluxRemote/1.0", forHTTPHeaderField: "User-Agent")
        
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            var errorMsg = "HTTP Error \(httpResponse.statusCode)"
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let msg = json["details"] as? String {
                    errorMsg = msg
                } else if let msg = json["error"] as? String {
                    errorMsg = msg
                }
            }
            
            throw NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    // Support for Encodable models
    func request<T: Decodable, B: Encodable>(_ path: String, method: String = "GET", encodableBody: B? = nil) async throws -> T {
        guard let baseURL = baseURL, let url = URL(string: path.hasPrefix("/") ? String(path.dropFirst()) : path, relativeTo: baseURL) else {
            throw NSError(domain: "APIClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "No Base URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15.0
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh-Hans;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.3.1 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        
        if let body = encodableBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        let (data, response) = try await session.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            var errorMsg = "HTTP Error \(httpResponse.statusCode)"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let msg = json["details"] as? String {
                    errorMsg = msg
                } else if let msg = json["error"] as? String {
                    errorMsg = msg
                }
            }
            throw NSError(domain: "APIClient", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    func fetchSettings() async {
        do {
            let response: ServerSettingsResponse = try await request("/api/settings")
            await MainActor.run {
                if let feats = response.data.features {
                    self.features = feats
                }
            }
        } catch {
            print("Fetch settings for features failed: \(error)")
        }
    }
}
