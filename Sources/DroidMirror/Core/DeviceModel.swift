import Foundation

public enum DeviceState: String, Sendable, CaseIterable {
    case device = "device"
    case unauthorized = "unauthorized"
    case offline = "offline"
    case authorizing = "authorizing"
    case connecting = "connecting"
    case unknown = "unknown"
    
    public var isReady: Bool {
        return self == .device
    }
    
    public var userFriendlyTitle: String {
        switch self {
        case .device:
            return "Connected"
        case .unauthorized:
            return "Unauthorized (Check Phone RSA Prompt)"
        case .offline:
            return "Device Offline"
        case .authorizing:
            return "Authorizing..."
        case .connecting:
            return "Connecting..."
        case .unknown:
            return "Unknown Status"
        }
    }
}

public enum DeviceTransport: String, Sendable {
    case usb = "USB"
    case wireless = "Wireless"
}

public struct DeviceModel: Identifiable, Hashable, Sendable {
    public var id: String { serial }
    public let serial: String
    public let state: DeviceState
    public let transport: DeviceTransport
    public let product: String?
    public let model: String?
    public let device: String?
    public let transportId: String?
    
    public init(
        serial: String,
        state: DeviceState,
        transport: DeviceTransport = .usb,
        product: String? = nil,
        model: String? = nil,
        device: String? = nil,
        transportId: String? = nil
    ) {
        self.serial = serial
        self.state = state
        self.transport = transport
        self.product = product
        self.model = model
        self.device = device
        self.transportId = transportId
    }
    
    public var displayName: String {
        if let model = model, !model.isEmpty {
            return model.replacingOccurrences(of: "_", with: " ")
        }
        if let device = device, !device.isEmpty {
            return device
        }
        return serial
    }
}
