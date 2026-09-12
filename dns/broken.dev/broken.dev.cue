package dns

import "gunk.dev/armstrong/schema"

domain: "broken.dev"

records: [...schema.#DNSRecord] & [
	// Web (broken.dev) — apex and www both point at the Google Cloud load
	// balancer serving the live site. Apex requires A since CNAME is not
	// allowed on a zone apex.
	{type: "A", name: "", content: "34.117.196.131"},
	{type: "A", name: "www", content: "34.117.196.131"},
]
