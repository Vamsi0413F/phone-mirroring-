import XCTest
@testable import DroidMirror

final class AdbOutputParserTests: XCTestCase {
    func testParseEmptyOutput() {
        let output = "List of devices attached\n\n"
        let devices = AdbService.parseDevicesOutput(output)
        XCTAssertTrue(devices.isEmpty)
    }
    
    func testParseConnectedUsbDevice() {
        let output = """
        List of devices attached
        0A121FDEE00018         device usb:337641472X product:shiba model:Pixel_8 device:shiba transport_id:1
        """
        let devices = AdbService.parseDevicesOutput(output)
        XCTAssertEqual(devices.count, 1)
        
        let dev = devices[0]
        XCTAssertEqual(dev.serial, "0A121FDEE00018")
        XCTAssertEqual(dev.state, .device)
        XCTAssertEqual(dev.transport, .usb)
        XCTAssertEqual(dev.product, "shiba")
        XCTAssertEqual(dev.model, "Pixel_8")
        XCTAssertEqual(dev.device, "shiba")
        XCTAssertEqual(dev.transportId, "1")
        XCTAssertEqual(dev.displayName, "Pixel 8")
        XCTAssertTrue(dev.state.isReady)
    }
    
    func testParseUnauthorizedDevice() {
        let output = """
        List of devices attached
        R58M32ABCDE            unauthorized usb:12345678X transport_id:3
        """
        let devices = AdbService.parseDevicesOutput(output)
        XCTAssertEqual(devices.count, 1)
        
        let dev = devices[0]
        XCTAssertEqual(dev.serial, "R58M32ABCDE")
        XCTAssertEqual(dev.state, .unauthorized)
        XCTAssertFalse(dev.state.isReady)
    }
    
    func testParseWirelessDevice() {
        let output = """
        List of devices attached
        192.168.1.105:5555     device product:raven model:Pixel_6_Pro device:raven transport_id:4
        """
        let devices = AdbService.parseDevicesOutput(output)
        XCTAssertEqual(devices.count, 1)
        
        let dev = devices[0]
        XCTAssertEqual(dev.serial, "192.168.1.105:5555")
        XCTAssertEqual(dev.state, .device)
        XCTAssertEqual(dev.transport, .wireless)
        XCTAssertEqual(dev.displayName, "Pixel 6 Pro")
    }
    
    func testParseMixedDevicesWithDaemonBanner() {
        let output = """
        * daemon not running; starting now at tcp:5037
        * daemon started successfully
        List of devices attached
        DEVICE123              device usb:1 product:a model:Phone_A device:a transport_id:1
        DEVICE456              offline transport_id:2
        10.0.0.12:5555         unauthorized transport_id:3
        """
        let devices = AdbService.parseDevicesOutput(output)
        XCTAssertEqual(devices.count, 3)
        XCTAssertEqual(devices[0].state, .device)
        XCTAssertEqual(devices[1].state, .offline)
        XCTAssertEqual(devices[2].state, .unauthorized)
        XCTAssertEqual(devices[2].transport, .wireless)
    }
}
