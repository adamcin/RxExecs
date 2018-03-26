//
//  ANSITests.swift
//  RxExecs
//

import XCTest
import RxSwift
import RxBlocking
@testable import RxExecs

class ANSITests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testParse() {
        //let nsString = NSMutableAttributedString(string: "")

        let ansiString = "before \u{1b}[34mblue \u{1b}[0mafter"
        let ansi = ANSI()
        let decoded = ansi.decodeANSI(encodedString: ansiString)
        
        print("decoded: \(decoded)")
        
        assert(decoded.string == "before blue after")

        let stripped = ansi.stripANSI(encodedString: ansiString)
        
        print("stripped: \(stripped)")
        
        assert(stripped.string == "before blue after")
    }
    
    func testContinuation() {
        let ansi = ANSI(font: NSFont(name: "Source Code Pro", size: 12.0)!, fgColor: NSColor.black)
        let ansiString = " \u{1B}[1mPlease note that these warnings are just used to help the Homebrew maintainers.\n"
        let ansiString2 = "with debugging if you file an issue. If everything you use Homebrew for is"
        
        let decoded = [ansiString, ansiString2].reduce((NSMutableAttributedString(string: ""), [SGRCode]())) { (pair, val) -> (NSMutableAttributedString, [SGRCode]) in
            let (nsa, open) = pair
            let (nsa2, open2) = ansi.decodeANSI(encodedString: val, openCodes: open)
            print("open: \(open), open2: \(open2)")
            nsa.append(nsa2)
            return (nsa, open2)
        }
        
        print("decoded: \(decoded.0)")
    }
}
