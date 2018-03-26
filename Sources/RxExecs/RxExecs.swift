//
//  RxExecExecutor.swift
//  RxExecs
//

import Foundation
import RxSwift

open class RxExecs {
    
    open class func launch(_ descriptor: RxExecDescriptorType, _ attach: ((_ process: RxExecFullyAttachableType) throws -> ())?) throws -> RxExecLaunchedType {
        let process = RxExecTask(descriptor: descriptor.asDescriptor())
        if let attach = attach {
            try attach(FullyAttachableProcessFacade(process))
        }
        process.launch()
        return LaunchedProcessFacade(process)
    }
    
    open class func launchPty(_ descriptor: RxExecDescriptorType, _ attach: ((_ process: RxExecInputAttachableType) throws -> ())?) throws -> RxExecLaunchedType {
        let process = RxExecPTY(descriptor: descriptor.asDescriptor())
        if let attach = attach {
            try attach(InputAttachableProcessFacade(process))
        }
        process.launch()
        return LaunchedProcessFacade(process)
    }
    
    class func dispatch(_ qosClass: DispatchQoS.QoSClass, _ block: @escaping ()->()) {
        DispatchQueue.global(qos: qosClass).async(execute: block)
    }
}
