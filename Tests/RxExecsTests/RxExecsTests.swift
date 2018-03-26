//
//  RxExecsTests.swift
//  RxExecsTests
//

import XCTest
import RxSwift
import RxBlocking
@testable import RxExecs

class RxExecsTests: XCTestCase {
    
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
    
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        let desc = RxExecDescriptor(path: "/bin/date", args: [String](), env: nil, cwd: "/tmp", qos: .userInitiated)
        let subject = PublishSubject<String>()
        
        let _ = subject.subscribe { (event) -> Void in
            switch event {
            case .next(let data): print("received data: \(data)")
            case .error(let error): print("encountered error: \(error)")
            case .completed: print("completed")
            }
        }
        
        let process = try! RxExecs.launch(desc) { (process) -> () in
            let _ = process.linesOut.subscribe(subject)
        }
        
        process.waitUntilExit()
    }
    
    func testOut() {
        let desc = RxExecDescriptor(path: pathForTestScript("hello_out"), args: nil, env: nil, cwd: "/tmp", qos: .userInitiated)
        
        var message = ""
        let subject = PublishSubject<String>()
        
        let _ = subject.subscribe { (event) in
            switch event {
            case .next(let line):
                print("\(desc); line: \(line)")
                if !line.isEmpty {
                    message = line
                }
            default: print("event: \(event)")
            }
        }
        
        let process = try! RxExecs.launch(desc) { (process) -> () in
            let _ = process.linesOut.subscribe(subject)
        }
        
        process.waitUntilExit()
        print("message: \(message)")
        XCTAssert(message == "Hello, World!")
    }
    
    func testOutPty() {
        let desc = RxExecDescriptor(path: pathForTestScript("hello_out"), args: nil, env: nil, cwd: "/tmp", qos: .userInitiated)
        
        var message = ""
        let subject = PublishSubject<String>()
        
        let _ = subject.subscribe { (event) in
            switch event {
            case .next(let line):
                print("\(desc); line: \(line)")
                if !line.isEmpty {
                    message = line
                }
            default: print("event: \(event)")
            }
        }
        
        let process = try! RxExecs.launchPty(desc) { (process) -> () in
            let _ = process.linesOut.subscribe(subject)
        }
        
        process.waitUntilExit()
        print("message: \(message)")
        XCTAssert(message == "Hello, World!")
    }
    
    func testErr() {
        let desc = RxExecDescriptor(path: pathForTestScript("hello_err"), args: nil, env: nil, cwd: "/tmp", qos: .userInitiated)
        
        var message = ""
        let subject = PublishSubject<String>()
        
        let _ = subject.subscribe { (event) in
            switch event {
            case .next(let line):
                print("line: \(line)")
                if !line.isEmpty {
                    message = line
                }
            case .error(let error): print("error \(error)"); fallthrough
            case .completed: print("completed")
            }
        }
        
        let process = try! RxExecs.launch(desc) { (process) -> () in
            let _ = process.linesErr.subscribe(subject)
        }
        
        process.waitUntilExit()
        XCTAssert(message == "Hello, World!")
    }
    
    func testIn() {
        let desc = RxExecDescriptor(path: pathForTestScript("hello_in"), args: nil, env: nil, cwd: "/tmp", qos: .userInitiated)
        
        var message = ""
        let linesIn = ReplaySubject<String>.create(bufferSize: 5)
        
        linesIn.on(.next("line 1"))
        linesIn.on(.next("line 3"))
        linesIn.on(.completed)
        
        let subject = PublishSubject<String>()
        
        let _ = subject.subscribe { (event) -> Void in
            switch event {
            case .next(let line):
                print("count: \(line)")
                if !line.isEmpty {
                    message = line
                }
            case .error(let error): print("error \(error)"); fallthrough
            case .completed: print("completed")
            }
        }
        
        let process = try! RxExecs.launch(desc) { (process) -> () in
            try process.attachTo(linesIn)
            let _ = process.linesOut.subscribe(subject)
        }
        
        process.waitUntilExit()
        print("message = \(message)")
        XCTAssert(message == "2")
    }
    
    func testInPty() {
        let desc = RxExecDescriptor(path: pathForTestScript("hello_in"), args: nil, env: nil, cwd: "/tmp", qos: .userInitiated)
        
        var message = ""
        let linesIn = ReplaySubject<String>.create(bufferSize: 5)
        
        linesIn.on(.next("line 1"))
        linesIn.on(.next("line 2"))
        linesIn.on(.next("line 3"))
        linesIn.on(.completed)
        
        let subject = PublishSubject<String>()
        
        let _ = subject.subscribe { (event) -> Void in
            switch event {
            case .next(let line):
                print("count: \(line)")
                if !line.isEmpty {
                    message = line
                }
            case .error(let error): print("error \(error)"); fallthrough
            case .completed: print("completed")
            }
        }
        
        let process = try! RxExecs.launchPty(desc) { (process) -> () in
            try process.attachTo(linesIn)
            let _ = process.linesOut.subscribe(subject)
        }
        
        process.waitUntilExit()
        print("message = \(message)")
        XCTAssert(message == "3")
    }
    
    func testExit() {
        let expected = Int(arc4random_uniform(256)) // bash only allows status codes between 0 and 255
        let desc = RxExecDescriptor(path: pathForTestScript("exit_code"), args: ["\(expected)"], env: nil, cwd: "/tmp", qos: .userInitiated)
        
        var status = -1
        let subject = PublishSubject<RxExecTermination>()
        
        let _ = subject.subscribe { (event) in
            switch event {
            case .next(let term):
                print("pid \(term.pid) terminated with status \(term.status)")
                status = term.status
            case .error(let error): print("error \(error)"); fallthrough
            case .completed: print("completed")
            }
        }
        
        let process = try! RxExecs.launch(desc) { (process) -> () in
            let _ = process.onTerm.subscribe(subject)
        }
        
        process.waitUntilExit()
        let _ = try! subject.toBlocking().last()
        print("status is \(status) and expected = \(expected); \(expected == status)")
        XCTAssert(status == expected)
    }
    
    func testSignal() {
        let desc = RxExecDescriptor(path: pathForTestScript("eternal"), args: nil, env: nil, cwd: "/tmp", qos: .userInitiated)
        
        var status = -1
        let subject = PublishSubject<RxExecTermination>()
        
        
        let scheduler = ConcurrentDispatchQueueScheduler(qos: .utility)
        let killer: Observable<Int> = Observable<Int>.interval(RxTimeInterval.init(1.0), scheduler: scheduler)
        
        let _ = subject.subscribe { (event) in
            switch event {
            case .next(let term):
                print("pid \(term.pid) terminated with status \(term.status)")
                status = term.status
            case .error(let error): print("error \(error)"); fallthrough
            case .completed: print("completed")
            }
        }
        
        let process = try! RxExecs.launch(desc) { (process) -> () in
            try process.attachTo(killer.map { _ -> RxExecSignal in return RxExecSignal.sigKill })
            let _ = process.linesOut.subscribe({ (event) in
                switch event {
                case .next(let line):
                    print(line)
                default: break;
                }
            })
            let _ = process.onTerm.subscribe(subject)
        }
        
        process.waitUntilExit()
        let _ = try! subject.toBlocking().last()
        
        XCTAssert(status > 0)
        
    }
    
    func testBrewDoctorPty() {
        let desc = RxExecDescriptor(path: "/bin/zsh", args: ["-c", "brew doctor"], env: ["TERM": "ansi", "HOME": NSHomeDirectory(), "PATH": "/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"], cwd: "/tmp", qos: .userInitiated)
        
        var message = ""
        let subject = PublishSubject<String>()
        
        let _ = subject.subscribe { (event) in
            switch event {
            case .next(let line):
                print("\(line)")
                if !line.isEmpty {
                    message = line
                }
            default: break;
            }
        }
        
        let process = try! RxExecs.launchPty(desc) { (process) -> () in
            let _ = process.linesOut.subscribe(subject)
        }
        
        process.waitUntilExit()
        print("message: \(message)")
    }
    
    func testLsPty() {
        //let desc = RxExecDescriptor(path: "/bin/ls", args: ["-GlaF", NSHomeDirectory()], env: ["TERM": "ansi", "HOME": NSHomeDirectory(), "PATH": "/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"], cwd: "/tmp", qos: .UserInitiated)
        let desc = RxExecDescriptor(path: "/bin/sh", args: ["-c", "ls -GlaF ~"], env: ["TERM": "ansi", "HOME": NSHomeDirectory(), "PATH": "/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"], cwd: "/tmp", qos: .userInitiated)
        
        var message = ""
        let subject = PublishSubject<String>()
        
        let _ = subject.subscribe { (event) in
            switch event {
            case .next(let line):
                print("\(line)", separator: "", terminator: "")
                if !line.isEmpty {
                    message = line
                }
            default: break;
            }
        }
        
        let process = try! RxExecs.launchPty(desc) { (process) -> () in
            let _ = process.stdOut.map { $0.toString() }.subscribe(subject)
        }
        
        process.waitUntilExit()
        print("message: \(message)")
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}
