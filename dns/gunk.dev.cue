package dns

import "gunk.dev/infra/schema"

domain: "gunk.dev"

records: [...schema.#DNSRecord] & [
	// Fastmail DKIM
	{type: "CNAME", name: "fm1._domainkey", content: "fm1.gunk.dev.dkim.fmhosted.com"},
	{type: "CNAME", name: "fm2._domainkey", content: "fm2.gunk.dev.dkim.fmhosted.com"},
	{type: "CNAME", name: "fm3._domainkey", content: "fm3.gunk.dev.dkim.fmhosted.com"},

	// Fastmail MX
	{type: "MX", name: "", content: "in1-smtp.messagingengine.com", priority: 10},
	{type: "MX", name: "", content: "in2-smtp.messagingengine.com", priority: 20},

	// TXT — email verification and SPF
	{type: "TXT", name: "", content: "google-site-verification=26VQTRvP0Q7wB3mhQPg4FRRKqMLMXq7US_kL2OxE0Nw"},
	{type: "TXT", name: "", content: "v=spf1 include:spf.messagingengine.com ?all"},

	// App CNAMEs
	{type: "CNAME", name: "flux", content: "flux-prod.fly.dev"},
	{type: "CNAME", name: "staging.flux", content: "flux-staging.fly.dev"},
	{type: "CNAME", name: "balance", content: "balance-prod.fly.dev"},
	{type: "CNAME", name: "staging.balance", content: "balance-staging.fly.dev"},
	{type: "CNAME", name: "staging.web", content: "gunk-web-staging.fly.dev"},

	// Web (gunk.dev) — apex requires A/AAAA since CNAME is not allowed on zone apex.
	// Verify these IPs after app creation: fly ips list -a gunk-web-prod
	{type: "A", name: "", content: "66.241.124.255"},
	{type: "AAAA", name: "", content: "2a09:8280:1::2:db55"},
	{type: "CNAME", name: "www", content: "gunk-web-prod.fly.dev"},
]
