import Foundation

enum NavigationItem: String, CaseIterable, Identifiable {
    case monitor, processes, logs, configs, launchagent, docker, nginx, settings, servers, more
    
    var id: String { self.rawValue }
    
    var title: String {
        switch self {
        case .monitor: return "sidebar.monitor"
        case .processes: return "sidebar.processes"
        case .logs: return "sidebar.logs"
        case .configs: return "sidebar.configs"
        case .launchagent: return "sidebar.launchagent"
        case .docker: return "sidebar.docker"
        case .nginx: return "sidebar.nginx"
        case .settings: return "sidebar.settings"
        case .servers: return "sidebar.servers"
        case .more: return "common.more"
        }
    }
    
    var icon: String {
        switch self {
        case .monitor: return "waveform.path.ecg.rectangle.fill"
        case .processes: return "cpu.fill"
        case .logs: return "long.text.page.and.pencil.fill"
        case .configs: return "document.badge.gearshape.fill"
        case .launchagent: return "paperplane.fill"
        case .docker: return "shippingbox.fill"
        case .nginx: return "server.rack"
        case .settings: return "slider.horizontal.3"
        case .servers: return "list.bullet.rectangle.portrait"
        case .more: return "ellipsis.circle.fill"
        }
    }
}
