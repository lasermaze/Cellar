import Testing
@testable import cellar

@Suite("CSRF — OriginCheckMiddleware")
struct OriginCheckMiddlewareTests {

    @Test("GET request passes regardless of origin")
    func getPassesAlways() {
        #expect(OriginCheckMiddleware.isOriginAllowed("http://evil.com", method: "GET", allowedPort: 8080))
    }

    @Test("POST with no Origin header passes (non-browser client)")
    func postNoOriginPasses() {
        #expect(OriginCheckMiddleware.isOriginAllowed(nil, method: "POST", allowedPort: 8080))
    }

    @Test("POST with localhost origin on correct port passes")
    func postLocalhostPasses() {
        #expect(OriginCheckMiddleware.isOriginAllowed("http://localhost:8080", method: "POST", allowedPort: 8080))
    }

    @Test("POST with 127.0.0.1 origin on correct port passes")
    func postLoopbackPasses() {
        #expect(OriginCheckMiddleware.isOriginAllowed("http://127.0.0.1:8080", method: "POST", allowedPort: 8080))
    }

    @Test("POST with evil origin is blocked")
    func postEvilOriginBlocked() {
        #expect(!OriginCheckMiddleware.isOriginAllowed("http://evil.com", method: "POST", allowedPort: 8080))
    }

    @Test("POST with localhost on wrong port is blocked")
    func postWrongPortBlocked() {
        #expect(!OriginCheckMiddleware.isOriginAllowed("http://localhost:9999", method: "POST", allowedPort: 8080))
    }

    @Test("DELETE with cross-origin is blocked")
    func deleteCrossOriginBlocked() {
        #expect(!OriginCheckMiddleware.isOriginAllowed("http://attacker.com", method: "DELETE", allowedPort: 8080))
    }

    @Test("PUT with no origin passes")
    func putNoOriginPasses() {
        #expect(OriginCheckMiddleware.isOriginAllowed(nil, method: "PUT", allowedPort: 8080))
    }

    @Test("PATCH with cross-origin is blocked")
    func patchCrossOriginBlocked() {
        #expect(!OriginCheckMiddleware.isOriginAllowed("http://evil.com", method: "PATCH", allowedPort: 8080))
    }

    @Test("Custom port is respected")
    func customPortRespected() {
        #expect(OriginCheckMiddleware.isOriginAllowed("http://localhost:3000", method: "POST", allowedPort: 3000))
        #expect(!OriginCheckMiddleware.isOriginAllowed("http://localhost:8080", method: "POST", allowedPort: 3000))
    }
}
