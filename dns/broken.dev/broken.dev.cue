package dns

import "gunk.dev/armstrong/schema"

domain: "broken.dev"

records: [...schema.#DNSRecord] & [
	// Web (broken.dev): the valley web edge, Fly app valley-web-prod, on its
	// dedicated addresses. Apex requires A/AAAA since CNAME is not allowed on
	// a zone apex.
	{type: "A", name: "", content: "149.248.210.213"},
	{type: "AAAA", name: "", content: "2a09:8280:1::1d3:2186:0"},
	{type: "CNAME", name: "www", content: "valley-web-prod.fly.dev"},
]
