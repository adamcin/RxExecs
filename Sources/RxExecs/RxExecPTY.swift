//
//  RxExecPTY.swift
//  RxExecs
//

import Foundation
import RxSwift


class RxExecPTY: RxExecInputAttachableType, RxExecLaunchedClassType {
    
    let descriptor: RxExecDescriptor
    
    fileprivate let task = PTY()
    
    fileprivate var signalObservables = [Observable<RxExecSignal>]()
    fileprivate let _sigObserver: SignalObserver
    let stdSig: AnyObserver<RxExecSignal>
    
    fileprivate let inputDisposables = DisposeBag()
    fileprivate var inputObservables = [Observable<Data>]()
    fileprivate var _inObserver: PipeInObserver?
    
    fileprivate let _outObservable: PipeOutObservable
    let stdOut: Observable<Data>
    
    let linesOut: Observable<String>
    
    fileprivate var _pid: Int? = nil
    
    var isLaunched: Bool { return _pid != nil }
    var isTerminated: Bool = false
    var pid: Int { return _pid! }
    
    fileprivate let termSubject = BehaviorSubject<RxExecTermination?>(value: nil)
    var onTerm: Observable<RxExecTermination> {
        return termSubject.filter { $0 != nil }.map { $0! }.asObservable()
    }
    
    internal init(descriptor: RxExecDescriptor) {
        self.descriptor = descriptor
        self.task.launchPath = descriptor.path
        
        if let args = descriptor.args {
            self.task.arguments = args
        }
        if let env = descriptor.env {
            self.task.environment = env
        }
        
        if let cwd = descriptor.cwd {
            self.task.currentDirectoryPath = cwd
        }
        self.task.qualityOfService = descriptor.qos
        
        let outPipe = Pipe()
        self.task.standardOutput = outPipe
        self._outObservable = PipeOutObservable(pipe: outPipe)
        self.stdOut = self._outObservable.asObservable()
        self.linesOut = TextStreamProducer(self.stdOut).asObservable()
        
        self._sigObserver = SignalObserver()
        self.stdSig = AnyObserver(self._sigObserver)
        self._sigObserver.process = self
    }
    
    fileprivate func internalAttachInputPipe() -> AnyObserver<Data> {
        if self._inObserver == nil {
            let inPipe = Pipe()
            self.task.standardInput = inPipe
            self._inObserver = PipeInObserver(pipe: inPipe)
        }
        
        return AnyObserver(self._inObserver!)
    }
    
    func attachTo(_ signalIn: Observable<RxExecSignal>) throws {
        if self.isLaunched {
            throw RxExecProcessError.inputAttachedAfterLaunch
        }
        signalIn.subscribe(self.stdSig).disposed(by: self.inputDisposables)
    }
    
    func attachTo(_ dataIn: Observable<Data>) throws {
        if self.isLaunched {
            throw RxExecProcessError.inputAttachedAfterLaunch
        }
        
        self.inputObservables += [dataIn]
    }
    
    func attachTo(_ linesIn: Observable<String>) throws {
        try self.attachTo(linesIn.map { (str) -> Data in
            return (str + "\n").data(using: String.Encoding.utf8)!
        })
    }
    
    internal func launch() {
        
        self.task.terminationHandler = { [weak self] (task) -> Void in
            guard let this = self else { return }
            this.isTerminated = true
            let lastData = this.task.masterFileHandle.readDataToEndOfFile()
            this._outObservable.subject.on(.next(lastData))
            this._outObservable.complete()
            let term: RxExecTermination = RxExecTermination(descriptor: this.descriptor, task: task)
            this.termSubject.on(.next(term))
            this.termSubject.on(.completed)
        }
        
        let pipe: AnyObserver<Data>? = self.inputObservables.isEmpty ? nil : self.internalAttachInputPipe()
        self._outObservable.readNext()
        self.task.launch()
        
        self._pid = Int(self.task.processIdentifier)
        
        // subscribe to all inputs
        if !self.signalObservables.isEmpty {
            Observable.merge(self.signalObservables).subscribe(self.stdSig).disposed(by: self.inputDisposables)
        }
        
        if let pipe = pipe {
            Observable.merge(self.inputObservables).subscribe(pipe).disposed(by: self.inputDisposables)
        }
    }
    
    func waitUntilExit() {
        self.task.waitUntilExit()
    }
    
}

