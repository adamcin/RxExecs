//
//  RxExecProcess.swift
//  RxExecs
//

import Foundation
import RxSwift

public enum RxExecSignal {
    case sigInt
    case sigKill
    case sigHup
    case sigQuit
    case sigTerm
    
    public func rawValue() -> Int32 {
        switch self {
        case .sigInt: return SIGINT
        case .sigKill: return SIGKILL
        case .sigHup: return SIGHUP
        case .sigQuit: return SIGQUIT
        case .sigTerm: return SIGTERM
        }
    }
}

internal class SignalObserver: ObserverType {
    typealias E = RxExecSignal
    
    weak var process: RxExecLaunchedClassType? = nil
    
    func on(_ event: Event<RxExecSignal>) {
        switch event {
        case .next(let signal):
            if let pid = self.process?.pid {
                kill(Int32(pid), signal.rawValue())
            }
        case .error(_): fallthrough
        case .completed: break
        }
        
    }
}

public struct RxExecTermination {
    public let pid: Int
    public let descriptor: RxExecDescriptor
    public let status: Int
    public let reason: Process.TerminationReason
    
    internal init(descriptor: RxExecDescriptor, task: RxExecUnderlyingProcessType) {
        self.pid = Int(task.processIdentifier)
        self.descriptor = descriptor
        self.status = Int(task.terminationStatus)
        self.reason = task.terminationReason
    }
}

public protocol RxExecType {
    var isLaunched: Bool { get }
    var descriptor: RxExecDescriptor { get }
    var onTerm: Observable<RxExecTermination> { get }
}

public protocol RxExecOutputAttachableType: RxExecType {
    func attachTo(_ signalIn: Observable<RxExecSignal>) throws
    var stdOut: Observable<Data> { get }
    var linesOut: Observable<String> { get }
}

public protocol RxExecErrorAttachableType: RxExecOutputAttachableType {
    var stdErr: Observable<Data> { get }
    var linesErr: Observable<String> { get }
}

public protocol RxExecInputAttachableType: RxExecOutputAttachableType {
    func attachTo(_ dataIn: Observable<Data>) throws
    func attachTo(_ linesIn: Observable<String>) throws
}

public protocol RxExecLaunchedType: RxExecOutputAttachableType {
    var pid: Int { get }
    var isTerminated: Bool { get }
    func waitUntilExit()
}

protocol RxExecLaunchedClassType: class, RxExecLaunchedType {
    
}

public protocol RxExecFullyAttachableType: RxExecInputAttachableType, RxExecErrorAttachableType {
    
}

class TextStreamObserver: ObserverType {
    typealias E = Data
    let subject = PublishSubject<String>()
    var buffer = ""
    
    func isNewline(_ char: Character) -> Bool {
        return char == "\n" || char == "\r\n"
    }
    
    func on(_ event: Event<Data>) {
        switch event {
        case .next(let data):
            let str = String(data: data, encoding: String.Encoding.utf8) ?? ""
            var combined = buffer + str
            buffer = ""
            let sendLast = combined.last.map(isNewline) ?? false
            var subs = [String]()
            while subs.count != 1 && !combined.isEmpty {
                subs = combined.split(maxSplits: 1, omittingEmptySubsequences: false, whereSeparator: isNewline).map { String.init($0) }
                
                if subs.count > 1 || sendLast {
                    self.subject.on(.next(subs[0]))
                }
                
                if subs.count > 1 {
                    combined = subs[1]
                } else {
                    buffer = subs[0]
                    combined = ""
                }
            }
        case .error(let error):
            self.subject.on(.error(error))
        case .completed:
            if !buffer.isEmpty {
                self.subject.on(.next(self.buffer))
            }
            self.subject.on(.completed)
        }
    }
}

class TextStreamProducer: ObservableConvertibleType {
    typealias E = String
    
    let dataStreamObservable: Observable<Data>
    let textObserver: TextStreamObserver
    
    init(_ dataStreamObservable: Observable<Data>) {
        self.dataStreamObservable = dataStreamObservable
        self.textObserver = TextStreamObserver()
    }
    
    func asObservable() -> Observable<TextStreamProducer.E> {
        return Observable.create({ (observer) -> Disposable in
            let textDisp = self.textObserver.subject.subscribe(observer)
            let dataDisp = self.dataStreamObservable.subscribe(self.textObserver)
            return CompositeDisposable(textDisp, dataDisp)
        })
    }
}

struct StringToDataStreamObserver: ObserverType {
    typealias E = String
    
    let dataObserver: AnyObserver<Data>
    init(_ dataObserver: AnyObserver<Data>) {
        self.dataObserver = dataObserver
    }
    
    func on(_ event: Event<String>) {
        switch event {
        case .next(let str):
            let data = (str + "\n").data(using: String.Encoding.utf8)!
            self.dataObserver.on(.next(data))
        case .error(let error):
            self.dataObserver.on(.error(error))
        case .completed:
            self.dataObserver.on(.completed)
        }
    }
}


internal class PipeOutObservable: ObservableType {
    typealias E = Data
    
    let handle: FileHandle
    let subject = PublishSubject<Data>()
    let qosClass: DispatchQoS.QoSClass
    
    init(pipe: Pipe, qosClass: DispatchQoS.QoSClass = DispatchQoS.QoSClass.userInitiated) {
        self.handle = pipe.fileHandleForReading
        self.qosClass = qosClass
    }
    
    func subscribe<O : ObserverType>(_ observer: O) -> Disposable where O.E == E {
        return self.subject.subscribe(observer)
    }
    
    func asObservable() -> Observable<Data> {
        return self.subject.asObservable()
    }
    
    internal func readNext() {
        RxExecs.dispatch(self.qosClass) { [weak self] () -> Void in
            guard let this = self else { return }
            let data = this.handle.availableData
            let doReadNext = data.count > 0
            this.subject.on(.next(data))
            if doReadNext {
                this.readNext()
            }
        }
    }
    
    fileprivate func readToEndOfFile() {
        let lastData = self.handle.readDataToEndOfFile()
        self.subject.on(.next(lastData))
    }
    
    internal func complete(_ readToEOF: Bool = false) {
        if readToEOF {
            self.readToEndOfFile()
        }
        self.subject.on(.next(Data()))
        self.subject.on(Event.completed)
    }
    
    deinit {
        self.complete()
        subject.dispose()
        handle.closeFile()
    }
}


internal class PipeInObserver: ObserverType {
    typealias E = Data
    let handle: FileHandle
    
    init(pipe: Pipe) {
        self.handle = pipe.fileHandleForWriting
    }
    
    func on(_ event: Event<Data>) {
        switch event {
        case .next(let data):
            self.handle.write(data)
        case .error(_): fallthrough
        case .completed:
            self.complete()
        }
    }
    
    internal func complete() {
        //self.handle.writeData(String(0x04, radix: 16, uppercase: false).dataUsingEncoding(NSUTF8StringEncoding)!)
        self.handle.write(Data())
        self.handle.closeFile()
    }
    
    deinit {
        self.complete()
    }
}


public enum RxExecProcessError: Error {
    case inputAttachedAfterLaunch
}

struct LaunchedProcessFacade: RxExecLaunchedType {
    fileprivate let process: RxExecLaunchedType
    
    init(_ process: RxExecLaunchedType) {
        self.process = process
    }
    
    var isLaunched: Bool { return process.isLaunched }
    var isTerminated: Bool { return process.isTerminated }
    var descriptor: RxExecDescriptor { return process.descriptor }
    
    func attachTo(_ signalIn: Observable<RxExecSignal>) throws { return try! process.attachTo(signalIn) }
    var stdOut: Observable<Data> { return process.stdOut }
    var linesOut: Observable<String> { return process.linesOut }
    
    var onTerm: Observable<RxExecTermination> { return process.onTerm }
    
    var pid: Int { return process.pid }
    func waitUntilExit() { process.waitUntilExit() }
}

struct OutputAttachableProcessFacade: RxExecOutputAttachableType {
    fileprivate let process: RxExecOutputAttachableType
    
    init(_ process: RxExecOutputAttachableType) {
        self.process = process
    }
    
    var isLaunched: Bool { return process.isLaunched }
    var descriptor: RxExecDescriptor { return process.descriptor }
    
    func attachTo(_ signalIn: Observable<RxExecSignal>) throws { return try! process.attachTo(signalIn) }
    var stdOut: Observable<Data> { return process.stdOut }
    var linesOut: Observable<String> { return process.linesOut }
    
    var onTerm: Observable<RxExecTermination> { return process.onTerm }
    
}

struct InputAttachableProcessFacade: RxExecInputAttachableType {
    fileprivate let process: RxExecInputAttachableType
    
    init(_ process: RxExecInputAttachableType) {
        self.process = process
    }
    
    var isLaunched: Bool { return process.isLaunched }
    var descriptor: RxExecDescriptor { return process.descriptor }
    
    var stdOut: Observable<Data> { return process.stdOut }
    var linesOut: Observable<String> { return process.linesOut }
    
    var onTerm: Observable<RxExecTermination> { return process.onTerm }
    
    func attachTo(_ signalIn: Observable<RxExecSignal>) throws { return try! process.attachTo(signalIn) }
    func attachTo(_ dataIn: Observable<Data>) throws { return try! process.attachTo(dataIn) }
    func attachTo(_ linesIn: Observable<String>) throws { return try! process.attachTo(linesIn) }
}

struct FullyAttachableProcessFacade: RxExecFullyAttachableType {
    fileprivate let process: RxExecFullyAttachableType
    
    init(_ process: RxExecFullyAttachableType) {
        self.process = process
    }
    
    var isLaunched: Bool { return process.isLaunched }
    var descriptor: RxExecDescriptor { return process.descriptor }
    
    var stdOut: Observable<Data> { return process.stdOut }
    var stdErr: Observable<Data> { return process.stdErr }
    
    var linesOut: Observable<String> { return process.linesOut }
    var linesErr: Observable<String> { return process.linesErr }
    
    var onTerm: Observable<RxExecTermination> { return process.onTerm }
    
    func attachTo(_ signalIn: Observable<RxExecSignal>) throws { return try! process.attachTo(signalIn) }
    func attachTo(_ dataIn: Observable<Data>) throws { return try! process.attachTo(dataIn) }
    func attachTo(_ linesIn: Observable<String>) throws { return try! process.attachTo(linesIn) }
}
