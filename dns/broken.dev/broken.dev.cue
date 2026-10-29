package dns

import "gunk.dev/armstrong/schema"

domain: "broken.dev"

records: [...schema.#DNSRecord] & [
	// Web (broken.dev): the valley web edge, Fly app valley-web-prod, on its
	// dedicated addresses. Apex and www both use A/AAAA: CNAME is not allowed
	// on a zone apex, and DNS sync creates before it prunes, so a www CNAME
	// can't replace the A record it held before.
	{type: "A", name: "", content: "149.248.210.213"},
	{type: "AAAA", name: "", content: "2a09:8280:1::1d3:2186:0"},
	{type: "A", name: "www", content: "149.248.210.213"},
	{type: "AAAA", name: "www", content: "2a09:8280:1::1d3:2186:0"},
]
