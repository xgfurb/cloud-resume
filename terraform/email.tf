# ============================================================
# EMAIL INFRASTRUCTURE — SimpleLogin (Proton Mail)
# ============================================================
# This file defines DNS records required for SimpleLogin to
# handle email for czresume.com. SimpleLogin acts as an alias
# relay — mail sent to any @czresume.com alias is forwarded
# to your Proton Mail inbox. You can reply from aliases
# without revealing your real address.
#
# No mailbox is hosted on this domain. SimpleLogin handles:
#   - Receiving mail (MX records)
#   - Sending replies from aliases (SPF + DKIM)
#   - Anti-spoofing protection (DMARC)
#
# IMPORTANT: After applying these records, go to SimpleLogin
# → Settings → Custom Domains and click "Verify" for each
# record type. DNS propagation may take a few minutes.
# ============================================================


# ────────────────────────────────────────────────────────────
# DOMAIN OWNERSHIP VERIFICATION
# ────────────────────────────────────────────────────────────
# SimpleLogin requires a TXT record to prove you own the
# domain before it will accept mail for it. This is a
# one-time verification — once confirmed, the record must
# stay in place.
# ────────────────────────────────────────────────────────────

resource "aws_route53_record" "simplelogin_verification" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 300

  # NOTE: If you later add SPF or other TXT records on the
  # root domain, they must ALL go in this single resource's
  # "records" list. Route 53 allows only one TXT record set
  # per name — multiple values are separate entries in the list.
  #
  # When SimpleLogin gives you the SPF record (a TXT record
  # starting with "v=spf1"), add it as a second entry here:
  #
  #   records = [
  #     "sl-verification=gvnaxeodfrjzexvzaocbsphjazkqsf",
  #     "v=spf1 include:simplelogin.co -all"
  #   ]
  records = [
    "sl-verification=gvnaxeodfrjzexvzaocbsphjazkqsf",
  ]
}


# ────────────────────────────────────────────────────────────
# MX RECORDS — Mail delivery
# ────────────────────────────────────────────────────────────
# MX (Mail eXchange) records tell the internet which servers
# handle incoming email for your domain. The priority number
# (first value) determines the order — lower = tried first.
#
# SimpleLogin provides two MX servers for redundancy. If the
# primary (priority 10) is down, mail falls back to the
# secondary (priority 20).
#
# PLACEHOLDER: Replace the values below with the exact MX
# records SimpleLogin gives you after domain verification.
# They'll look something like:
#   "10 mx1.simplelogin.co."
#   "20 mx2.simplelogin.co."
# ────────────────────────────────────────────────────────────

# resource "aws_route53_record" "simplelogin_mx" {
#   zone_id = aws_route53_zone.main.zone_id
#   name    = var.domain_name
#   type    = "MX"
#   ttl     = 300
#
#   records = [
#     "10 mx1.simplelogin.co.",
#     "20 mx2.simplelogin.co.",
#   ]
# }


# ────────────────────────────────────────────────────────────
# DKIM RECORDS — Email signing
# ────────────────────────────────────────────────────────────
# DKIM (DomainKeys Identified Mail) lets SimpleLogin
# cryptographically sign outgoing emails so receiving servers
# can verify the message wasn't tampered with in transit.
#
# SimpleLogin typically provides 2-3 CNAME records that point
# to their DKIM key servers. The record names and values will
# look something like:
#   Name:  dkim._domainkey.czresume.com
#   Value: dkim._domainkey.simplelogin.co.
#
# PLACEHOLDER: Uncomment and fill in the exact CNAME records
# SimpleLogin gives you. The number of records may vary.
# ────────────────────────────────────────────────────────────

# resource "aws_route53_record" "simplelogin_dkim1" {
#   zone_id = aws_route53_zone.main.zone_id
#   name    = "dkim._domainkey.${var.domain_name}"
#   type    = "CNAME"
#   ttl     = 300
#
#   records = ["dkim._domainkey.simplelogin.co."]
# }

# resource "aws_route53_record" "simplelogin_dkim2" {
#   zone_id = aws_route53_zone.main.zone_id
#   name    = "dkim2._domainkey.${var.domain_name}"
#   type    = "CNAME"
#   ttl     = 300
#
#   records = ["dkim2._domainkey.simplelogin.co."]
# }

# resource "aws_route53_record" "simplelogin_dkim3" {
#   zone_id = aws_route53_zone.main.zone_id
#   name    = "dkim3._domainkey.${var.domain_name}"
#   type    = "CNAME"
#   ttl     = 300
#
#   records = ["dkim3._domainkey.simplelogin.co."]
# }


# ────────────────────────────────────────────────────────────
# DMARC RECORD — Anti-spoofing policy
# ────────────────────────────────────────────────────────────
# DMARC (Domain-based Message Authentication, Reporting &
# Conformance) tells receiving mail servers what to do when
# an email claiming to be from your domain fails SPF and
# DKIM checks.
#
# p=reject  — reject emails that fail authentication (strongest
#             policy — no one can spoof your domain)
# rua=      — where to send aggregate DMARC reports (optional;
#             use a czresume.com alias so reports land in your
#             Proton Mail inbox)
#
# PLACEHOLDER: Uncomment after MX and DKIM are verified.
# ────────────────────────────────────────────────────────────

# resource "aws_route53_record" "dmarc" {
#   zone_id = aws_route53_zone.main.zone_id
#   name    = "_dmarc.${var.domain_name}"
#   type    = "TXT"
#   ttl     = 300
#
#   records = [
#     "v=DMARC1; p=reject; rua=mailto:dmarc@czresume.com"
#   ]
# }
