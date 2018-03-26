//
//  PTYTests.swift
//  RxExecs
//

import XCTest
import RxSwift
import RxBlocking
@testable import RxExecs

class PTYTests: XCTestCase {
    override func setUp() {
        super.setUp()
        
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func pathForTestScript(_ name: String) -> String {
        return Bundle(for: type(of: self)).path(forResource: name, ofType: ".sh")!
    }
    
    func doSomethingContinuously(_ closure: @escaping () -> ()) {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let this = self else { return }
            closure()
            sleep(1)
            this.doSomethingContinuously(closure)
        }
    }
    
    func testStdInPTY() {
        let lsPty = PTY(path: pathForTestScript("hello_in"), args: ["-GlaF", NSHomeDirectory()], envDict: ["TERM": "ansi", "HOME": NSHomeDirectory()])
        //let lsPty = PTY(path: "/bin/cat", args: [], envDict: ["TERM": "ansi", "HOME": NSHomeDirectory()])
        var status: Int32 = -3
        
        print("final status: \(status)")
        lsPty.terminationHandler = { (pty: PTY) -> Void in
            status = pty.terminationStatus
        }
        
        let linesIn = ReplaySubject<String>.create(bufferSize: 5)
        
        linesIn.on(.next("line 1"))
        linesIn.on(.next("line 3"))
        linesIn.on(.completed)
        
        let stdin = Pipe()
        lsPty.standardInput = stdin
        
        let pipeIn = PipeInObserver(pipe: stdin)
        
        let _ = linesIn.subscribe(StringToDataStreamObserver(AnyObserver(pipeIn)))
        
        let stdout = Pipe()
        lsPty.standardOutput = stdout
        
        let pipeOut = PipeOutObservable(pipe: stdout)
        
        let _ = pipeOut.subscribe { (event) in
            switch event {
            case .next(let data):
                print(String.init(data: data, encoding: String.Encoding.utf8) ?? "", separator: "", terminator: "")
            default: break
            }
        }
        
        lsPty.launch()
        
        print("forked child: \(lsPty.childProcessID)")
        
        //print(lsPty.masterFileHandle.readDataToEndOfFile().toString())
        
        doSomethingContinuously { () -> () in
            print("waiting ...")
        }
        
        lsPty.waitUntilExit()
        
        //lsPty.waitUntilChildProcessFinishes()
        
        sleep(5)
        print("final status: \(status)")
    }
    
    func testPTY() {
        let lsPty = PTY(path: "/bin/ls", args: ["-GlaF", NSHomeDirectory()], envDict: ["TERM": "ansi", "HOME": NSHomeDirectory()])
        var status: Int32 = -3
        
        print("final status: \(status)")
        lsPty.terminationHandler = { (pty: PTY) -> Void in
            status = pty.terminationStatus
        }
        
        let stdout = Pipe()
        lsPty.standardOutput = stdout
        
        let pipeOut = PipeOutObservable(pipe: stdout)
        
        let _ = pipeOut.subscribe { (event) in
            switch event {
            case .next(let data):
                print(String.init(data: data, encoding: String.Encoding.utf8) ?? "", separator: "", terminator: "")
            default: break
            }
        }
        
        pipeOut.readNext()
        lsPty.launch()
        
        print("forked child: \(lsPty.childProcessID)")
        
        //print(lsPty.masterFileHandle.readDataToEndOfFile().toString())
        
        doSomethingContinuously { () -> () in
            print("waiting ...")
        }
        
        lsPty.waitUntilExit()
        
        //lsPty.waitUntilChildProcessFinishes()
        
        sleep(5)
        print("final status: \(status)")
    }
}
