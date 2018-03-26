//
//  RxExecDescriptor.swift
//  RxExecs
//

import Foundation

public protocol RxExecDescriptorType {
    var path: String { get }
    var qos: QualityOfService { get }
    var args: [String]? { get }
    var env: [String : String]? { get } // if not set, use current
    var cwd: String? { get }  // if not set, use current

    
    func asDescriptor() -> RxExecDescriptor
}

public struct RxExecDescriptor : RxExecDescriptorType, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    public let path: String
    public let args: [String]?
    public let env: [String : String]? // if not set, use current
    public let cwd: String? // if not set, use current
    public let qos: QualityOfService
    
    public init(path: String, args: [String]?, env: [String: String]?, cwd: String, qos: QualityOfService) {
        self.path = path
        self.args = args
        self.env = env
        self.cwd = cwd
        self.qos = qos
    }
    
    public var description: String {
        return "\(type(of: self))(path: \(path), args: \(String(describing: args)), env: \(String(describing: env)), cwd: \(String(describing: cwd)), qos: \(qos.name()))"
    }
    
    public var debugDescription: String { return self.description }

    public var hashValue: Int {
        return self.description.hashValue
    }
    
    public func asDescriptor() -> RxExecDescriptor {
        return self
    }
}

extension QualityOfService {
    func name() -> String {
        switch self {
        case .default: return "Default"
        case .background: return "Background"
        case .userInitiated: return "UserInitiated"
        case .userInteractive: return "UserInteractive"
        case .utility: return "Utility"
        }
    }
}

public func ==(left: RxExecDescriptor, right: RxExecDescriptor) -> Bool {
    return left.description == right.description
}
