import Foundation

/// Bundled DNS templates (verbatim port of RN `services/dns-templates.ts`;
/// values verified upstream against provider docs — links kept per template).
nonisolated struct DnsTemplate: Identifiable, Sendable, Equatable {
    struct Placeholder: Sendable, Equatable {
        let key: String
        let label: String
        let placeholder: String
        let required: Bool
    }

    struct Record: Sendable, Equatable {
        let type: DNSRecordType
        let name: String   // '@', literal label, or '{{target}}'
        let content: String
        var ttl: Int? = 1
        var proxied: Bool? = false
        var priority: Int?
        var comment: String?
    }

    enum Category: String, CaseIterable, Sendable {
        case hosting, email, verification, security
    }

    let id: String
    let name: String
    let category: Category
    let description: String
    let icon: String
    let color: String
    let domain: String?
    let placeholders: [Placeholder]
    /// choosable = user picks apex or subdomain; fixed = same records always.
    let targetModeChoosable: Bool
    var apexRecords: [Record]?
    var subdomainRecords: [Record]?
    var records: [Record]?
    let docs: String?
}

nonisolated enum DnsTemplateLibrary {
    /// All 20 bundled templates.
    static let all: [DnsTemplate] = [
        // ── Hosting (choosable apex/subdomain) ─────────────────────────
        DnsTemplate(
            id: "vercel", name: "Vercel", category: .hosting,
            description: "Point apex or a subdomain to a Vercel project",
            icon: "cloud", color: "#000000", domain: "vercel.com",
            placeholders: [], targetModeChoosable: true,
            apexRecords: [
                .init(type: .a, name: "@", content: "76.76.21.21", ttl: 1, proxied: true, comment: "Vercel apex"),
            ],
            subdomainRecords: [
                .init(type: .cname, name: "{{target}}", content: "cname.vercel-dns.com", ttl: 1, proxied: true, comment: "Vercel subdomain"),
            ],
            docs: "https://vercel.com/docs/projects/domains/working-with-domains"
        ),
        DnsTemplate(
            id: "netlify", name: "Netlify", category: .hosting,
            description: "Point apex or a subdomain to a Netlify site",
            icon: "cloud", color: "#00C7B7", domain: "netlify.com",
            placeholders: [.init(key: "site", label: "Netlify Site", placeholder: "your-site.netlify.app", required: true)],
            targetModeChoosable: true,
            apexRecords: [
                .init(type: .a, name: "@", content: "75.2.60.5", ttl: 1, proxied: true, comment: "Netlify apex"),
            ],
            subdomainRecords: [
                .init(type: .cname, name: "{{target}}", content: "{{site}}", ttl: 1, proxied: true, comment: "Netlify subdomain"),
            ],
            docs: "https://docs.netlify.com/domains-https/custom-domains/"
        ),
        DnsTemplate(
            id: "github-pages", name: "GitHub Pages", category: .hosting,
            description: "Point apex or a subdomain to GitHub Pages",
            icon: "code", color: "#181717", domain: "github.com",
            placeholders: [.init(key: "username", label: "GitHub Username/Org", placeholder: "your-username", required: true)],
            targetModeChoosable: true,
            apexRecords: [
                .init(type: .a, name: "@", content: "185.199.108.153", ttl: 1, proxied: false, comment: "GitHub Pages"),
                .init(type: .a, name: "@", content: "185.199.109.153", ttl: 1, proxied: false, comment: "GitHub Pages"),
                .init(type: .a, name: "@", content: "185.199.110.153", ttl: 1, proxied: false, comment: "GitHub Pages"),
                .init(type: .a, name: "@", content: "185.199.111.153", ttl: 1, proxied: false, comment: "GitHub Pages"),
            ],
            subdomainRecords: [
                .init(type: .cname, name: "{{target}}", content: "{{username}}.github.io", ttl: 1, proxied: false, comment: "GitHub Pages"),
            ],
            docs: "https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site"
        ),
        DnsTemplate(
            id: "cloudflare-pages", name: "Cloudflare Pages", category: .hosting,
            description: "Point apex or a subdomain to a Cloudflare Pages project",
            icon: "doc", color: "#F6821F", domain: "pages.cloudflare.com",
            placeholders: [.init(key: "project", label: "Project Name", placeholder: "your-project", required: true)],
            targetModeChoosable: true,
            apexRecords: [
                .init(type: .cname, name: "@", content: "{{project}}.pages.dev", ttl: 1, proxied: true, comment: "Cloudflare Pages apex"),
            ],
            subdomainRecords: [
                .init(type: .cname, name: "{{target}}", content: "{{project}}.pages.dev", ttl: 1, proxied: true, comment: "Cloudflare Pages subdomain"),
            ],
            docs: "https://developers.cloudflare.com/pages/configuration/custom-domains/"
        ),
        DnsTemplate(
            id: "render", name: "Render", category: .hosting,
            description: "Point apex or a subdomain to a Render service",
            icon: "cloud", color: "#46E3B7", domain: "render.com",
            placeholders: [.init(key: "service", label: "Render Service", placeholder: "your-service.onrender.com", required: true)],
            targetModeChoosable: true,
            apexRecords: [
                .init(type: .a, name: "@", content: "216.24.57.1", ttl: 1, proxied: true, comment: "Render apex"),
            ],
            subdomainRecords: [
                .init(type: .cname, name: "{{target}}", content: "{{service}}", ttl: 1, proxied: true, comment: "Render subdomain"),
            ],
            docs: "https://render.com/docs/custom-domains"
        ),
        DnsTemplate(
            id: "fly-io", name: "Fly.io", category: .hosting,
            description: "Point apex or a subdomain to a Fly.io app",
            icon: "cloud", color: "#7B3AED", domain: "fly.io",
            placeholders: [
                .init(key: "app", label: "Fly App Name", placeholder: "your-app", required: true),
                .init(key: "ipv4", label: "IPv4 (apex only)", placeholder: "flyctl ips list", required: false),
                .init(key: "ipv6", label: "IPv6 (apex only)", placeholder: "flyctl ips list", required: false),
            ],
            targetModeChoosable: true,
            apexRecords: [
                .init(type: .a, name: "@", content: "{{ipv4}}", ttl: 1, proxied: false, comment: "Fly.io apex IPv4"),
                .init(type: .aaaa, name: "@", content: "{{ipv6}}", ttl: 1, proxied: false, comment: "Fly.io apex IPv6"),
            ],
            subdomainRecords: [
                .init(type: .cname, name: "{{target}}", content: "{{app}}.fly.dev", ttl: 1, proxied: false, comment: "Fly.io subdomain"),
            ],
            docs: "https://fly.io/docs/networking/custom-domains-with-fly/"
        ),
        DnsTemplate(
            id: "heroku", name: "Heroku", category: .hosting,
            description: "Point a subdomain to a Heroku app (apex not officially supported)",
            icon: "cloud", color: "#430098", domain: "heroku.com",
            placeholders: [.init(key: "dns_target", label: "Heroku DNS Target", placeholder: "lookup with: heroku domains", required: true)],
            targetModeChoosable: true,
            apexRecords: [
                .init(type: .cname, name: "@", content: "{{dns_target}}", ttl: 1, proxied: true, comment: "Heroku apex (CF flatten)"),
            ],
            subdomainRecords: [
                .init(type: .cname, name: "{{target}}", content: "{{dns_target}}", ttl: 1, proxied: false, comment: "Heroku subdomain"),
            ],
            docs: "https://devcenter.heroku.com/articles/custom-domains"
        ),

        // ── Email (fixed) ──────────────────────────────────────────────
        DnsTemplate(
            id: "google-workspace", name: "Google Workspace", category: .email,
            description: "MX record for Google Workspace (single MX as of 2023)",
            icon: "envelope", color: "#4285F4", domain: "workspace.google.com",
            placeholders: [], targetModeChoosable: false,
            records: [
                .init(type: .mx, name: "@", content: "smtp.google.com", ttl: 1, proxied: nil, priority: 1, comment: "Google Workspace"),
            ],
            docs: "https://support.google.com/a/answer/140034"
        ),
        DnsTemplate(
            id: "microsoft-365", name: "Microsoft 365", category: .email,
            description: "MX, SPF, and autodiscover for Microsoft 365 mail",
            icon: "envelope", color: "#0078D4", domain: "microsoft.com",
            placeholders: [.init(key: "tenant", label: "M365 MX target", placeholder: "yourdomain-com.mail.protection.outlook.com", required: true)],
            targetModeChoosable: false,
            records: [
                .init(type: .mx, name: "@", content: "{{tenant}}", ttl: 1, proxied: nil, priority: 0, comment: "Microsoft 365 MX"),
                .init(type: .txt, name: "@", content: "v=spf1 include:spf.protection.outlook.com -all", ttl: 1, comment: "M365 SPF"),
                .init(type: .cname, name: "autodiscover", content: "autodiscover.outlook.com", ttl: 1, comment: "M365 autodiscover"),
            ],
            docs: "https://learn.microsoft.com/en-us/microsoft-365/admin/setup/add-domain"
        ),
        DnsTemplate(
            id: "zoho-mail", name: "Zoho Mail", category: .email,
            description: "MX and SPF records for Zoho Mail",
            icon: "envelope", color: "#E42527", domain: "zoho.com",
            placeholders: [], targetModeChoosable: false,
            records: [
                .init(type: .mx, name: "@", content: "mx.zoho.com", ttl: 1, proxied: nil, priority: 10, comment: "Zoho Mail"),
                .init(type: .mx, name: "@", content: "mx2.zoho.com", ttl: 1, proxied: nil, priority: 20, comment: "Zoho Mail"),
                .init(type: .mx, name: "@", content: "mx3.zoho.com", ttl: 1, proxied: nil, priority: 50, comment: "Zoho Mail"),
                .init(type: .txt, name: "@", content: "v=spf1 include:zoho.com ~all", ttl: 1, comment: "Zoho SPF"),
            ],
            docs: "https://www.zoho.com/mail/help/adminconsole/configure-email-delivery.html"
        ),
        DnsTemplate(
            id: "sendgrid", name: "SendGrid", category: .email,
            description: "CNAME record for SendGrid sender authentication",
            icon: "envelope", color: "#1A82E2", domain: "sendgrid.com",
            placeholders: [
                .init(key: "subdomain", label: "CNAME prefix", placeholder: "em1234", required: true),
                .init(key: "target", label: "SendGrid target", placeholder: "u1234.wl.sendgrid.net", required: true),
            ],
            targetModeChoosable: false,
            records: [
                .init(type: .cname, name: "{{subdomain}}", content: "{{target}}", ttl: 1, proxied: false, comment: "SendGrid"),
            ],
            docs: "https://docs.sendgrid.com/ui/account-and-settings/how-to-set-up-domain-authentication"
        ),
        DnsTemplate(
            id: "mailgun", name: "Mailgun", category: .email,
            description: "MX and SPF for a Mailgun sending subdomain",
            icon: "envelope", color: "#F8BC2F", domain: "mailgun.com",
            placeholders: [.init(key: "domain", label: "Mailgun subdomain", placeholder: "mg", required: true)],
            targetModeChoosable: false,
            records: [
                .init(type: .mx, name: "{{domain}}", content: "mxa.mailgun.org", ttl: 1, proxied: nil, priority: 10, comment: "Mailgun MX"),
                .init(type: .mx, name: "{{domain}}", content: "mxb.mailgun.org", ttl: 1, proxied: nil, priority: 10, comment: "Mailgun MX"),
                .init(type: .txt, name: "{{domain}}", content: "v=spf1 include:mailgun.org ~all", ttl: 1, comment: "Mailgun SPF"),
            ],
            docs: "https://documentation.mailgun.com/en/latest/quickstart-sending.html"
        ),

        // ── Verification (fixed) ───────────────────────────────────────
        DnsTemplate(
            id: "google-site-verify", name: "Google Site Verification", category: .verification,
            description: "TXT record to verify domain ownership with Google",
            icon: "checkmark.seal", color: "#4285F4", domain: "google.com",
            placeholders: [.init(key: "token", label: "Verification token", placeholder: "google-site-verification=...", required: true)],
            targetModeChoosable: false,
            records: [
                .init(type: .txt, name: "@", content: "{{token}}", ttl: 1, comment: "Google verification"),
            ],
            docs: "https://support.google.com/webmasters/answer/9008080"
        ),
        DnsTemplate(
            id: "microsoft-verify", name: "Microsoft Verification", category: .verification,
            description: "TXT record to verify domain ownership with Microsoft",
            icon: "checkmark.seal", color: "#0078D4", domain: "microsoft.com",
            placeholders: [.init(key: "token", label: "Verification token", placeholder: "MS=ms...", required: true)],
            targetModeChoosable: false,
            records: [
                .init(type: .txt, name: "@", content: "{{token}}", ttl: 1, comment: "Microsoft verification"),
            ],
            docs: nil
        ),
        DnsTemplate(
            id: "facebook-verify", name: "Facebook/Meta Verification", category: .verification,
            description: "TXT record to verify domain ownership with Meta",
            icon: "checkmark.seal", color: "#1877F2", domain: "facebook.com",
            placeholders: [.init(key: "token", label: "Verification token", placeholder: "facebook-domain-verification=...", required: true)],
            targetModeChoosable: false,
            records: [
                .init(type: .txt, name: "@", content: "{{token}}", ttl: 1, comment: "Facebook verification"),
            ],
            docs: nil
        ),

        // ── Security (fixed) ───────────────────────────────────────────
        DnsTemplate(
            id: "spf-default", name: "Default SPF Record", category: .security,
            description: "Strict SPF allowing only your MX servers",
            icon: "shield", color: "#10B981", domain: nil,
            placeholders: [], targetModeChoosable: false,
            records: [
                .init(type: .txt, name: "@", content: "v=spf1 mx -all", ttl: 1, comment: "SPF strict"),
            ],
            docs: nil
        ),
        DnsTemplate(
            id: "dmarc-monitor", name: "DMARC (Monitor mode)", category: .security,
            description: "DMARC record in monitoring mode (p=none)",
            icon: "shield", color: "#10B981", domain: nil,
            placeholders: [.init(key: "rua", label: "Reports email", placeholder: "reports@yourdomain.com", required: true)],
            targetModeChoosable: false,
            records: [
                .init(type: .txt, name: "_dmarc", content: "v=DMARC1; p=none; rua=mailto:{{rua}}; ruf=mailto:{{rua}}; fo=1", ttl: 1, comment: "DMARC monitor"),
            ],
            docs: "https://dmarc.org/overview/"
        ),
        DnsTemplate(
            id: "dmarc-reject", name: "DMARC (Reject mode)", category: .security,
            description: "DMARC record with strict reject policy",
            icon: "shield", color: "#EF4444", domain: nil,
            placeholders: [.init(key: "rua", label: "Reports email", placeholder: "reports@yourdomain.com", required: true)],
            targetModeChoosable: false,
            records: [
                .init(type: .txt, name: "_dmarc", content: "v=DMARC1; p=reject; rua=mailto:{{rua}}; ruf=mailto:{{rua}}; fo=1; aspf=s; adkim=s", ttl: 1, comment: "DMARC reject"),
            ],
            docs: nil
        ),
        DnsTemplate(
            id: "caa-letsencrypt", name: "CAA — Let's Encrypt only", category: .security,
            description: "Allow only Let's Encrypt to issue certificates",
            icon: "lock", color: "#10B981", domain: nil,
            placeholders: [], targetModeChoosable: false,
            records: [
                .init(type: .caa, name: "@", content: "0 issue \"letsencrypt.org\"", ttl: 1, comment: "CAA Let's Encrypt"),
            ],
            docs: nil
        ),
        DnsTemplate(
            id: "block-email", name: "Block Email (no MX)", category: .security,
            description: "Reject all incoming email and lock SPF (RFC 7505)",
            icon: "lock", color: "#EF4444", domain: nil,
            placeholders: [], targetModeChoosable: false,
            records: [
                .init(type: .mx, name: "@", content: ".", ttl: 1, proxied: nil, priority: 0, comment: "Null MX"),
                .init(type: .txt, name: "@", content: "v=spf1 -all", ttl: 1, comment: "No-mail SPF"),
                .init(type: .txt, name: "_dmarc", content: "v=DMARC1; p=reject; sp=reject", ttl: 1, comment: "No-mail DMARC"),
            ],
            docs: "https://datatracker.ietf.org/doc/html/rfc7505"
        ),
    ]

    static func template(id: String) -> DnsTemplate? {
        all.first { $0.id == id }
    }
}

/// Expands a template into concrete `DNSRecordInput`s (RN `applyTemplate` parity).
nonisolated enum TemplateExpander {
    struct Options {
        var values: [String: String] = [:]
        var useSubdomain: Bool = false
        /// Subdomain label when `useSubdomain` (e.g. "www"); unused for apex.
        var targetName: String = "www"
    }

    static func apply(_ template: DnsTemplate, options: Options) -> [DNSRecordInput] {
        let source: [DnsTemplate.Record]
        if template.targetModeChoosable {
            source = options.useSubdomain ? (template.subdomainRecords ?? []) : (template.apexRecords ?? [])
        } else {
            source = template.records ?? []
        }

        var substitutions = options.values
        // Implicit {{target}}: forced for choosable templates; for fixed templates a
        // user-supplied `target` placeholder (e.g. SendGrid) wins over the default.
        if template.targetModeChoosable {
            substitutions["target"] = options.useSubdomain ? (options.targetName.trimmingCharacters(in: .whitespaces).isEmpty ? "www" : options.targetName) : "@"
        } else {
            substitutions["target"] = substitutions["target"] ?? "@"
        }

        func replace(_ string: String) -> String {
            var result = string
            for (key, value) in substitutions where !value.isEmpty {
                result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
            }
            return result
        }

        return source.map { record in
            DNSRecordInput(
                type: record.type,
                name: replace(record.name),
                content: replace(record.content),
                ttl: record.ttl ?? 1,
                proxied: record.proxied,
                priority: record.priority,
                comment: record.comment.map(replace)
            )
        }
    }
}
