package dns

import "gunk.dev/infra/schema"

domain: "gunk.dev"

records: [...schema.#DNSRecord] & [
	// Flux
	{type: "CNAME", name: "flux", content: "flux-prod.fly.dev"},
	{type: "CNAME", name: "staging.flux", content: "flux-staging.fly.dev"},

	// Balance
	{type: "CNAME", name: "balance", content: "balance-prod.fly.dev"},
	{type: "CNAME", name: "staging.balance", content: "balance-staging.fly.dev"},
]
