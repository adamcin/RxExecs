//
//  PTY.swift
//  RxExecs

import Foundation
import Darwin

///	Provides simple access to Darwin `pty`.
///
///	This spawns a new child process using supplied arguments,
///	and setup a proper pseudo terminal connected to it.
///
///	The child process will run in interactive mode terminal,
///	and will emit terminal escape code accordingly if you set
///	a proper terminal environment variable.
///
///		TERM=ansi
///
///	Here's full recommended example.
///
///		let	pty	= PTY(path: "/bin/ls", arguments: ["-Gbla"], environment: ["TERM": "ansi"])!
///		println(pty.masterFileHandle.readDataToEndOfFile().toString())
///		pty.waitUntilChildProcessFinishes()
///
///	It is recommended to use executable name as the first argument by convention.
///
///	The child process will be launched immediately when you
///	instantiate this class.
///
///	This is a sort of `NSTask`-like class and modeled on it.
///	This does not support setting terminal dimensions.
///

open class PTY: RxExecUnderlyingProcessType {
    
    // these methods can only be set before a launch
    open var launchPath: String? = nil
    open var arguments: [String]? = nil
    open var environment: [String : String]? = nil // if not set, use current
    open var currentDirectoryPath: String = FileManager().currentDirectoryPath // if not set, use current
    
    // actions
    open func launch() {
        self.internalLaunch(self.launchPath!, argv: [self.launchPath!] + (self.arguments ?? []), env: (self.environment ?? ProcessInfo.processInfo.environment).map { "\($0)=\($1)" })
    }
    
    // status
    open var processIdentifier: Int32 = -2
    open var running: Bool = false
    
    open var terminationStatus: Int32 = -2
    
    open var terminationReason: Process.TerminationReason = Process.TerminationReason.exit
    
    /*
    A block to be invoked when the process underlying the NSTask terminates.  Setting the block to nil is valid, and stops the previous block from being invoked, as long as it hasn't started in any way.  The NSTask is passed as the argument to the block so the block does not have to capture, and thus retain, it.  The block is copied when set.  Only one termination handler block can be set at any time.  The execution context in which the block is invoked is undefined.  If the NSTask has already finished, the block is executed immediately/soon (not necessarily on the current thread).  If a terminationHandler is set on an NSTask, the NSTaskDidTerminateNotification notification is not posted for that task.  Also note that -waitUntilExit won't wait until the terminationHandler has been fully executed.  You cannot use this property in a concrete subclass of NSTask which hasn't been updated to include an implementation of the storage and use of it.
    */
    open var terminationHandler: ((PTY) -> Void)?
    
    open var qualityOfService: QualityOfService = QualityOfService.default
    
    fileprivate var	_masterFileHandle: FileHandle?
    fileprivate var	_childProcessID: pid_t? {
        willSet {
            if let newValue = newValue {
                self.processIdentifier = Int32(newValue)
            }
        }
    }
    
    open var masterFileHandle: FileHandle { return _masterFileHandle! }
    open var childProcessID: pid_t { return _childProcessID! }
    
    open var standardInput: Pipe?
    open var standardOutput: Pipe?
    
    fileprivate var canReadFromStdin = false
    fileprivate var canReadFromMaster = false
    
    fileprivate func beginReadingFromPipe(_ stdin: Pipe, master: FileHandle) {
        RxExecs.dispatch(self.qosClass) { [weak self, weak stdin, weak master] () -> Void in
            guard let this = self, let stdin = stdin else { return }
            let data = stdin.fileHandleForReading.availableData
            guard let master = master else { return }
            let readAgain = data.count > 0
            if readAgain {
                master.write(data)
                this.beginReadingFromPipe(stdin, master: master)
            }
        }
    }
    
    fileprivate func beginWritingToPipe(_ master: FileHandle, stdout: Pipe) {
        RxExecs.dispatch(self.qosClass) { [weak self, weak master, weak stdout] () -> Void in
            guard let this = self, let master = master else { return }
            let data = master.availableData
            guard let stdout = stdout else { return }
            let readAgain = data.count > 0
            if readAgain {
                stdout.fileHandleForWriting.write(data)
                this.beginWritingToPipe(master, stdout: stdout)
            }
        }
    }
    
    fileprivate func internalLaunch(_ path: String, argv: [String], env: [String]) {
        print("internalLaunch(path: \(path), argv: \(argv), env: \(env))")
        let r = RxExecForkPty()
        if r.result.ok {
            if r.result.isRunningInParentProcess {
                self._childProcessID = r.result.processID
                self._masterFileHandle = r.master.toFileHandle(true)
                
                let stdout = self.standardOutput ?? Pipe()
                
                beginWritingToPipe(self._masterFileHandle!, stdout: stdout)
                
                if let stdin = self.standardInput {
                    
                    beginReadingFromPipe(stdin, master: self._masterFileHandle!)
                }
                
                self.running = true
                waitForProcess()
            } else {
                FileManager().changeCurrentDirectoryPath(self.currentDirectoryPath)
                RxExecPtyExec(path, args: argv, env: env)
                fatalError("Returning from `execute` means the command was failed. This is unrecoverable error in child process side, so just abort the execution.")
            }
        } else {
            // do something here?
        }
    }
    
    public init() {
        
    }
    
    public init(path: String, args: [String], envDict: [String: String]) {
        self.launchPath = path
        self.arguments = args
        self.environment = envDict
    }

    fileprivate var completionSemaphore: DispatchSemaphore? = DispatchSemaphore(value: 0)
    
    fileprivate var qosClass: DispatchQoS.QoSClass {
        switch self.qualityOfService {
        case .background: return DispatchQoS.QoSClass.background
        case .userInteractive: return DispatchQoS.QoSClass.userInteractive
        case .userInitiated: return DispatchQoS.QoSClass.userInitiated
        case .utility: return DispatchQoS.QoSClass.utility
        case .default: return DispatchQoS.QoSClass.default
        }
    }
    
    fileprivate func waitForProcess() {
        RxExecs.dispatch(DispatchQoS.QoSClass.background) { [weak self] in
            guard let this = self else { return }
            var	stat_loc = siginfo_t()
            let s = waitid(P_PID, UInt32(this.childProcessID), &stat_loc, WEXITED)
            
            if s <= 0 && stat_loc.si_pid == 0 {
                this.waitForProcess()
            } else {
                var status = stat_loc.si_status
                var reason: Process.TerminationReason = .exit
                if stat_loc.si_code == CLD_KILLED || stat_loc.si_code == CLD_DUMPED {
                    status = 130
                    reason = Process.TerminationReason.uncaughtSignal
                }
                this.terminate(status, reason: reason)
            }
        }
    }
    
    fileprivate func terminate(_ status: Int32, reason: Process.TerminationReason){
        self.running = false
        
        self.terminationReason = reason
        self.terminationStatus = status
        
        if let termHandler = self.terminationHandler {
            termHandler(self)
        }

        if let sema = self.completionSemaphore {
            self.completionSemaphore = nil
            sema.signal()
        }
        
    }
    
    ///	Waits for child process finishes synchronously.
    open func waitUntilExit(_ timeout: DispatchTime = DispatchTime.distantFuture) {
        if let sema = self.completionSemaphore {
            let _ = sema.wait(timeout: timeout)
        }
    }
}

struct FileDescriptor {
    fileprivate var value: Int32
    
    func toFileHandle(_ closeOnDealloc: Bool) -> FileHandle {
        return FileHandle(fileDescriptor: value, closeOnDealloc: closeOnDealloc)
    }
}

struct ForkResult {
    fileprivate var value: pid_t
    
    var ok: Bool { return value != -1 }
    var isRunningInParentProcess: Bool { return value > 0 }
    var isRunningInChildProcess: Bool { return value == 0 }
    var processID: pid_t {
        precondition(isRunningInParentProcess, "You tried to read this property from child process side. It is not allowed.")
        return value
    }
}

func RxExecForkPty() -> (result: ForkResult, master: FileDescriptor) {
    var termp = termios()
    //cfmakeraw(&termp)
    termp.c_iflag |= UInt(ICANON)
    var aMaster = 0 as Int32
    let pid = forkpty(&aMaster, nil, &termp, nil)
    return (ForkResult(value: pid), FileDescriptor(value: aMaster))
}

///	Generates proper pointer arrays for `exec~` family calls.
///	Terminatin `NULL` is required for `exec~` family calls.
func RxExecWithCPointerToNullTerminatingCArrayOfCStrings(_ strings: [String], block: (UnsafePointer<UnsafeMutablePointer<Int8>?>) -> ()) {
    ///	Keep this in memory until the `block` to be finished.
    let a1: [UnsafeMutablePointer<Int8>?] = strings.map { $0.utf8CString }.map { (d: ContiguousArray<CChar>) in
        let ptr: UnsafeMutablePointer<Int8> = UnsafeMutablePointer<Int8>.allocate(capacity: d.count + 1)
        d.withUnsafeBufferPointer({ (bufPtr) -> Void in
            if let address = bufPtr.baseAddress {
                ptr.initialize(from: address, count: bufPtr.count)
            }
        })
        return ptr
    } + [nil]
    
    a1.withUnsafeBufferPointer { (p: UnsafeBufferPointer<UnsafeMutablePointer<Int8>?>) -> () in
        if let address = p.baseAddress {
            block(address)
        }
    }
}

func RxExecPtyExec(_ path: String, args: [String], env: [String]) {
    path.withCString { (pathP: UnsafePointer<Int8>) -> () in
        RxExecWithCPointerToNullTerminatingCArrayOfCStrings(args, block: { (argP: UnsafePointer<UnsafeMutablePointer<Int8>?>) -> () in
            RxExecWithCPointerToNullTerminatingCArrayOfCStrings(env, block: { (envP: UnsafePointer<UnsafeMutablePointer<Int8>?>) -> () in
                execve(pathP, argP, envP)
                return
            })
        })
        fatalError("`execve` call returned, which indicates a failure")
    }
}

