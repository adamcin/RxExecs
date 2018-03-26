//
//  RxExecUnderlyingProcessType.swift
//  RxExecs
//

import Foundation

protocol RxExecUnderlyingProcessType {

    // these methods can only be set before a launch
    var launchPath: String? { get set }
    var arguments: [String]? { get set }
    var environment: [String : String]? { get set } // if not set, use current
    var currentDirectoryPath: String { get set } // if not set, use current
    
    // actions
    func launch()
    
    // status
    var processIdentifier: Int32 { get }
    var running: Bool { get }
    
    var terminationStatus: Int32 { get }
    @available(OSX 10.6, *)
    var terminationReason: Process.TerminationReason { get }
    
    var qualityOfService: QualityOfService { get set } // read-only after the task is launched
    
}

extension Process: RxExecUnderlyingProcessType {
    var running: Bool {
        get {
            return self.isRunning
        }
    }
}
