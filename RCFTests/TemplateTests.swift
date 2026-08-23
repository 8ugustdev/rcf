import XCTest
@testable import RCF

/// Template library integrity + expander placeholder substitution.
final class TemplateTests: XCTestCase {
    func testLibraryHasTwentyTemplatesAcrossCategories() {
        XCTAssertEqual(DnsTemplateLibrary.all.count, 20)
        XCTAssertEqual(Set(DnsTemplateLibrary.all.map(\.category)).count, 4)
        // ids unique
        XCTAssertEqual(Set(DnsTemplateLibrary.all.map(\.id)).count, 20)
    }

    func testVercelApexExpansion() {
        let template = DnsTemplateLibrary.template(id: "vercel")!
        let inputs = TemplateExpander.apply(template, options: .init(values: [:], useSubdomain: false))
        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(inputs[0].type, .a)
        XCTAssertEqual(inputs[0].name, "@")
        XCTAssertEqual(inputs[0].content, "76.76.21.21")
        XCTAssertEqual(inputs[0].proxied, true)
        XCTAssertEqual(inputs[0].ttl, 1)
    }

    func testVercelSubdomainDefaultTarget() {
        let template = DnsTemplateLibrary.template(id: "vercel")!
        let inputs = TemplateExpander.apply(template, options: .init(values: [:], useSubdomain: true, targetName: ""))
        XCTAssertEqual(inputs[0].type, .cname)
        XCTAssertEqual(inputs[0].name, "www") // blank target falls back to www
        XCTAssertEqual(inputs[0].content, "cname.vercel-dns.com")
    }

    func testCustomTargetName() {
        let template = DnsTemplateLibrary.template(id: "vercel")!
        let inputs = TemplateExpander.apply(template, options: .init(values: [:], useSubdomain: true, targetName: "app"))
        XCTAssertEqual(inputs[0].name, "app")
    }

    func testPlaceholderSubstitutionInContentAndComment() {
        let template = DnsTemplateLibrary.template(id: "microsoft-365")!
        let inputs = TemplateExpander.apply(template, options: .init(values: ["tenant": "acme-com.mail.protection.outlook.com"]))
        XCTAssertEqual(inputs.count, 3)
        XCTAssertEqual(inputs[0].content, "acme-com.mail.protection.outlook.com")
        XCTAssertEqual(inputs[0].priority, 0)
        // TXT SPF untouched (no placeholders)
        XCTAssertEqual(inputs[1].content, "v=spf1 include:spf.protection.outlook.com -all")
    }

    func testSendGridTwoPlaceholders() {
        let template = DnsTemplateLibrary.template(id: "sendgrid")!
        let inputs = TemplateExpander.apply(template, options: .init(values: ["subdomain": "em1234", "target": "u1.wl.sendgrid.net"]))
        XCTAssertEqual(inputs[0].name, "em1234")
        XCTAssertEqual(inputs[0].content, "u1.wl.sendgrid.net")
    }

    func testGitHubPagesApexHasFourARecords() {
        let template = DnsTemplateLibrary.template(id: "github-pages")!
        let apex = TemplateExpander.apply(template, options: .init(values: ["username": "octocat"], useSubdomain: false))
        XCTAssertEqual(apex.count, 4)
        XCTAssertTrue(apex.allSatisfy { $0.type == .a && $0.proxied == false })
        let sub = TemplateExpander.apply(template, options: .init(values: ["username": "octocat"], useSubdomain: true, targetName: "www"))
        XCTAssertEqual(sub.count, 1)
        XCTAssertEqual(sub[0].content, "octocat.github.io")
    }

    func testDmarcMonitorEmailSubstitution() {
        let template = DnsTemplateLibrary.template(id: "dmarc-monitor")!
        let inputs = TemplateExpander.apply(template, options: .init(values: ["rua": "postmaster@example.com"]))
        XCTAssertEqual(inputs[0].name, "_dmarc")
        XCTAssertTrue(inputs[0].content.contains("rua=mailto:postmaster@example.com"))
    }

    func testBlockEmailNullMX() {
        let template = DnsTemplateLibrary.template(id: "block-email")!
        let inputs = TemplateExpander.apply(template, options: .init())
        XCTAssertEqual(inputs.count, 3)
        XCTAssertEqual(inputs[0].type, .mx)
        XCTAssertEqual(inputs[0].content, ".")
        XCTAssertEqual(inputs[0].priority, 0)
    }
}

/// DNS import multipart body + endpoint shapes.
final class DNSEndpointTests: XCTestCase {
    func testImportMultipartContainsProxiedAndFile() {
        let request = CloudflareEndpoint.importDNSZone(zoneId: "z1", fileData: Data("example.com. 1 IN A 1.2.3.4".utf8), filename: "zone.txt", proxied: true)
        guard case let .multipart(body) = request.body else {
            return XCTFail("expected multipart body")
        }
        let encoded = String(decoding: body.encoded(), as: UTF8.self)
        XCTAssertTrue(encoded.contains("name=\"proxied\"\r\n\r\ntrue"))
        XCTAssertTrue(encoded.contains("name=\"file\"; filename=\"zone.txt\""))
        XCTAssertTrue(encoded.contains("example.com. 1 IN A 1.2.3.4"))
        XCTAssertEqual(request.path, "/zones/z1/dns_records/import")
        XCTAssertEqual(request.method, .post)
    }

    func testRecordsListFilters() {
        let request = CloudflareEndpoint.dnsRecords(zoneId: "z1", page: 2, type: "A", name: "www")
        XCTAssertEqual(request.path, "/zones/z1/dns_records")
        let queryItems = request.query.map(\.name)
        XCTAssertTrue(queryItems.contains("type"))
        XCTAssertTrue(queryItems.contains("name"))
        XCTAssertTrue(queryItems.contains("page"))
    }
}
